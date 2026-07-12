/**
 * Copyright (c) 2016-present, Parse, LLC.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import BoltsSwift
import Starscream

/**
 This is the 'advanced' view of live query subscriptions. It allows you to customize your subscriptions
 to a live query server, have connections to multiple servers, cleanly handle disconnect and reconnect.
 */
@objc(PFLiveQueryClient)
open class Client: NSObject {
    final class QueueState {
        var socket: WebSocket?
        var shouldPrintWebSocketLog = true
        var shouldPrintWebSocketTrace = false
        var userDisconnected = false
        var isConnecting = false
        var nextRequestId = 0
        var subscriptions = [SubscriptionRecord]()

        func makeRequestId() -> RequestId {
            nextRequestId += 1
            return RequestId(value: nextRequestId)
        }
    }

    let host: URL
    let applicationId: String
    let clientKey: String?

    let queue = DispatchQueue(label: "com.parse.livequery", attributes: [])
    private let queueState = QueueState()
    private let queueKey = DispatchSpecificKey<UInt8>()

    public var shouldPrintWebSocketLog: Bool {
        get { withQueueStateSync { $0.shouldPrintWebSocketLog } }
        set { withQueueStateSync { $0.shouldPrintWebSocketLog = newValue } }
    }

    public var shouldPrintWebSocketTrace: Bool {
        get { withQueueStateSync { $0.shouldPrintWebSocketTrace } }
        set { withQueueStateSync { $0.shouldPrintWebSocketTrace = newValue } }
    }

    public var userDisconnected: Bool {
        get { withQueueStateSync { $0.userDisconnected } }
        set { withQueueStateSync { $0.userDisconnected = newValue } }
    }

    /**
     Creates a Client which automatically attempts to connect to the custom parse-server URL set in Parse.currentConfiguration().
     */
    public override convenience init() {
        self.init(server: Parse.validatedCurrentConfiguration().server)
    }

    /**
     Creates a client which will connect to a specific server with an optional application id and client key

     - parameter server:        The server to connect to
     - parameter applicationId: The application id to use
     - parameter clientKey:     The client key to use
     */
    @objc(initWithServer:applicationId:clientKey:)
    public init(server: String, applicationId: String? = nil, clientKey: String? = nil) {
        guard let cmpts = URLComponents(string: server) else {
            fatalError("Server should be a valid URL.")
        }
        var components = cmpts
        components.scheme = (components.scheme == "https" || components.scheme == "wss") ? "wss" : "ws"

        self.applicationId = applicationId ?? Parse.validatedCurrentConfiguration().applicationId!
        self.clientKey = clientKey ?? Parse.validatedCurrentConfiguration().clientKey

        self.host = components.url!

        super.init()

        queue.setSpecific(key: queueKey, value: 1)
    }

    /// Runs synchronous state access on the client queue, executing inline when
    /// a callback re-enters the client from that queue.
    func withQueueStateSync<T>(_ body: (QueueState) throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body(queueState)
        }
        return try queue.sync {
            try body(queueState)
        }
    }

    /// Enqueues asynchronous state access in FIFO order. Always enqueueing keeps
    /// the existing Bolts task timing while remaining safe for reentrant calls.
    func withQueueStateAsync<T>(_ body: @escaping (QueueState) throws -> T) -> Task<T> {
        let state = queueState
        return Task(.queue(queue)) {
            try body(state)
        }
    }
}

extension Client {
    // Swift is lame and doesn't allow storage to directly be in extensions.
    // So we create an inner struct to wrap it up.
    fileprivate final class Storage: @unchecked Sendable {
        static let shared = Storage()

        let queue: DispatchQueue = DispatchQueue(label: "com.parse.livequery.client.storage", attributes: [])
        var client: Client?
    }

    /// Gets or sets shared live query client to be used for default subscriptions
    @objc(sharedClient)
    public static var shared: Client! {
        get {
            let storage = Storage.shared
            var client: Client?
            storage.queue.sync {
                client = storage.client
                if client == nil {
                    let configuration = Parse.validatedCurrentConfiguration()
                    client = Client(
                        server: configuration.server,
                        applicationId: configuration.applicationId,
                        clientKey: configuration.clientKey
                    )
                    storage.client = client
                }
            }
            return client
        }
        set {
            let storage = Storage.shared
            storage.queue.sync {
                storage.client = newValue
            }
        }
    }
}

extension Client {
    /**
     Registers a query for live updates, using the default subscription handler

     - parameter query:        The query to register for updates.
     - parameter subclassType: The subclass of PFObject to be used as the type of the Subscription.
     This parameter can be automatically inferred from context most of the time

     - returns: The subscription that has just been registered
     */
    public func subscribe<T>(
        _ query: PFQuery<T>,
        subclassType: T.Type = T.self
        ) -> Subscription<T> {
        return subscribe(query, handler: Subscription<T>())
    }

    /**
     Registers a query for live updates, using a custom subscription handler

     - parameter query:   The query to register for updates.
     - parameter handler: A custom subscription handler.

     - returns: Your subscription handler, for easy chaining.
    */
    public func subscribe<T>(
        _ query: PFQuery<T.PFObjectSubclass>,
        handler: T
        ) -> T where T: SubscriptionHandling {
        withQueueStateSync { state in
            subscribe(query, handler: handler, state: state)
        }
    }

    private func subscribe<T>(
        _ query: PFQuery<T.PFObjectSubclass>,
        handler: T,
        state: QueueState
        ) -> T where T: SubscriptionHandling {
        let subscriptionRecord = SubscriptionRecord(
            query: query,
            requestId: state.makeRequestId(),
            handler: handler
        )

        state.subscriptions.append(subscriptionRecord)

        if state.socket != nil {
            _ = self.sendOperationAsync(.subscribe(requestId: subscriptionRecord.requestId, query: query as! PFQuery<PFObject>,
            sessionToken: PFUser.current()?.sessionToken))
        } else if !state.userDisconnected {
            self.reconnect()
            state.subscriptions.removeLast()
            return self.subscribe(query, handler: handler, state: state)
        } else {
            NSLog("ParseLiveQuery: Warning: The client was explicitly disconnected! You must explicitly call .reconnect() in order to process your subscriptions.")
        }

        return handler
    }

    /**
     Updates an existing subscription with a new query.
     Upon completing the registration, the subscribe handler will be called with the new query

     - parameter handler: The specific handler to update.
     - parameter query:   The new query for that handler.
     */
    public func update<T>(
        _ handler: T,
        toQuery query: PFQuery<T.PFObjectSubclass>
        ) where T: SubscriptionHandling {
        withQueueStateSync { state in
            state.subscriptions = state.subscriptions.map {
                if $0.subscriptionHandler === handler {
                    _ = sendOperationAsync(.update(requestId: $0.requestId, query: query as! PFQuery<PFObject>))
                    return SubscriptionRecord(query: query, requestId: $0.requestId, handler: $0.subscriptionHandler as! T)
                }
                return $0
            }
        }
    }

    /**
     Unsubscribes all current subscriptions for a given query.

     - parameter query: The query to unsubscribe from.
     */
    @objc(unsubscribeFromQuery:)
    public func unsubscribe(_ query: PFQuery<PFObject>) {
        unsubscribe { $0.query == query }
    }

    /**
     Unsubscribes from a specific query-handler pair.

     - parameter query:   The query to unsubscribe from.
     - parameter handler: The specific handler to unsubscribe from.
     */
    public func unsubscribe<T>(_ query: PFQuery<T.PFObjectSubclass>, handler: T) where T: SubscriptionHandling {
        unsubscribe { $0.query == query && $0.subscriptionHandler === handler }
    }

    func unsubscribe(matching matcher: (SubscriptionRecord) -> Bool) {
        withQueueStateSync { state in
            var temp = [SubscriptionRecord]()
            state.subscriptions.forEach {
                if matcher($0) {
                    _ = sendOperationAsync(.unsubscribe(requestId: $0.requestId))
                } else {
                    temp.append($0)
                }
            }
            state.subscriptions = temp
        }
    }
}

extension Client {
    /**
     Reconnects this client to the server.

     This will disconnect and resubscribe all existing subscriptions. This is not required to be called the first time
     you use the client, and should usually only be called when an error occurs.
    */
    @objc(reconnect)
    public func reconnect() {
        withQueueStateSync { state in
            guard state.socket == nil || !state.isConnecting else { return }
            state.socket?.disconnect()
            let socket = WebSocket(request: .init(url: host))
            socket.delegate = self
            socket.callbackQueue = queue
            socket.connect()
            state.isConnecting = true
            state.userDisconnected = false
            state.socket = socket
        }
    }

    /**
     Explicitly disconnects this client from the server.

     This does not remove any subscriptions - if you `reconnect()` your existing subscriptions will be restored.
     Use this if you wish to dispose of the live query client.
    */
    @objc(disconnect)
    public func disconnect() {
        withQueueStateSync { state in
            state.isConnecting = false
            guard let socket = state.socket else {
                return
            }
            socket.disconnect()
            state.socket = nil
            state.userDisconnected = true
        }
    }
}
