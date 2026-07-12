//
//  ParseMessagingLiveQueryClient.swift
//  MessagingPersistence
//

import Foundation
import MessagingContracts
import ParseSwift

/// Full Parse LiveQuery adapter for the conversation aggregate. A dedicated
/// ParseLiveQuery client provides connection errors without replacing another
/// feature's global delegate.
public final class ParseMessagingLiveQueryClient: MessagingRealtimeClient {
    private let client: ParseLiveQuery
    private let authenticatedUserID: MessagingUserID
    private let lock = NSLock()
    private var disconnectHandlers: [UUID: (MessagingRealtimeEvent) -> Void] = [:]
    private var connectionGates: [UUID: LiveQueryConnectionGate] = [:]

    public init(
        authenticatedUserID: MessagingUserID,
        client: ParseLiveQuery? = nil
    ) throws {
        self.authenticatedUserID = authenticatedUserID
        if let client = client {
            self.client = client
        } else {
            self.client = try ParseLiveQuery(notificationQueue: .main)
        }
        self.client.receiveDelegate = self
    }

    public func subscribe(
        conversationIDs: Set<MessagingConversationID>,
        eventHandler: @escaping (MessagingRealtimeEvent) -> Void
    ) throws -> MessagingRealtimeSubscription {
        let tokenID = UUID()
        let token = ParseMessagingLiveQueryToken()

        let ids = conversationIDs.sorted()
        let pointers = ids.map { Pointer<MessagingParseConversation>(objectId: $0) }
        var expectedNames: Set<String> = ["membershipDiscovery"]
        if !ids.isEmpty {
            expectedNames.formUnion(["conversation", "member", "message", "reaction", "receipt"])
        }
        let connectionGate = LiveQueryConnectionGate(
            expectedSubscriptionNames: expectedNames,
            eventHandler: eventHandler
        )
        register(
            disconnectHandler: eventHandler,
            connectionGate: connectionGate,
            id: tokenID
        )
        token.addCancellation { [weak self] in self?.removeSubscriptionState(id: tokenID) }

        do {
            let currentUser = Pointer<MessagingParseUser>(objectId: authenticatedUserID)
            try addSubscription(
                name: "membershipDiscovery",
                query: MessagingParseConversationMember.query("user" == currentUser),
                token: token,
                tokenID: tokenID,
                gate: connectionGate
            ) { event in
                let object: MessagingParseConversationMember
                switch event {
                case .created(let value), .entered(let value), .updated(let value),
                     .left(let value), .deleted(let value):
                    object = value
                }
                guard let conversationID = object.conversation?.objectId else {
                    throw MessagingModelError.missingField(
                        className: MessagingParseConversationMember.className,
                        field: "conversation"
                    )
                }
                if !conversationIDs.contains(conversationID) ||
                    object.active != true ||
                    object.isHidden == true {
                    return .conversationSetInvalidated(conversationID: conversationID)
                }
                return nil
            }

            guard !ids.isEmpty else { return token }

            try addSubscription(
                name: "conversation",
                query: MessagingParseConversation.query(
                    containedIn(key: "objectId", array: ids)
                ),
                token: token,
                tokenID: tokenID,
                gate: connectionGate
            ) { event in
                switch event {
                case .created(let object), .entered(let object), .updated(let object):
                    return .conversationUpserted(try object.snapshot())
                case .left(let object), .deleted(let object):
                    var snapshot = try object.snapshot()
                    snapshot.isDeleted = true
                    return .conversationUpserted(snapshot)
                }
            }

            try addSubscription(
                name: "member",
                query: MessagingParseConversationMember.query(
                    containedIn(key: "conversation", array: pointers)
                ),
                token: token,
                tokenID: tokenID,
                gate: connectionGate
            ) { event in
                switch event {
                case .created(let object), .entered(let object), .updated(let object),
                     .left(let object), .deleted(let object):
                    return .memberUpserted(try object.snapshot())
                }
            }

            try addSubscription(
                name: "message",
                query: MessagingParseMessage.query(
                    containedIn(key: "conversation", array: pointers)
                ),
                token: token,
                tokenID: tokenID,
                gate: connectionGate
            ) { event in
                switch event {
                case .created(let object), .entered(let object), .updated(let object):
                    let snapshot = try object.snapshot()
                    return snapshot.isDeleted
                        ? .messageDeleted(snapshot)
                        : .messageUpserted(snapshot)
                case .left(let object), .deleted(let object):
                    var snapshot = try object.snapshot()
                    snapshot.isDeleted = true
                    return .messageDeleted(snapshot)
                }
            }

            try addSubscription(
                name: "reaction",
                query: MessagingParseReaction.query(
                    containedIn(key: "conversation", array: pointers)
                ),
                token: token,
                tokenID: tokenID,
                gate: connectionGate
            ) { event in
                switch event {
                case .created(let object), .entered(let object), .updated(let object):
                    return .reactionUpserted(try object.snapshot())
                case .left(let object), .deleted(let object):
                    var snapshot = try object.snapshot()
                    snapshot.isDeleted = true
                    return .reactionUpserted(snapshot)
                }
            }

            try addSubscription(
                name: "receipt",
                query: MessagingParseReceipt.query(
                    containedIn(key: "conversation", array: pointers)
                ),
                token: token,
                tokenID: tokenID,
                gate: connectionGate
            ) { event in
                switch event {
                case .created(let object), .entered(let object), .updated(let object):
                    return .receiptUpserted(try object.snapshot())
                case .left, .deleted:
                    return nil
                }
            }
        } catch {
            token.cancel()
            throw error
        }

        return token
    }

    private func addSubscription<T: ParseObject>(
        name: String,
        query: Query<T>,
        token: ParseMessagingLiveQueryToken,
        tokenID: UUID,
        gate: LiveQueryConnectionGate,
        transform: @escaping (Event<T>) throws -> MessagingRealtimeEvent?
    ) throws {
        let callback = SubscriptionCallback(query: query)
        callback.handleSubscribe { _, _ in gate.didSubscribe(name: name) }
        callback.handleEvent { [weak self] _, event in
            do {
                if let mapped = try transform(event) {
                    self?.notify(mapped, to: tokenID)
                }
            } catch {
                self?.notify(
                    .disconnected(errorDescription: String(describing: error)),
                    to: tokenID
                )
            }
        }
        let subscription = try Query<T>.subscribe(callback, client: client)
        token.addCancellation { [weak client] in
            guard let client = client else { return }
            try? query.unsubscribe(subscription, client: client)
        }
    }

    private func register(
        disconnectHandler handler: @escaping (MessagingRealtimeEvent) -> Void,
        connectionGate: LiveQueryConnectionGate,
        id: UUID
    ) {
        lock.lock()
        disconnectHandlers[id] = handler
        connectionGates[id] = connectionGate
        lock.unlock()
    }

    private func removeSubscriptionState(id: UUID) {
        lock.lock()
        disconnectHandlers[id] = nil
        connectionGates[id] = nil
        lock.unlock()
    }

    private func notify(_ event: MessagingRealtimeEvent) {
        lock.lock()
        let handlers = Array(disconnectHandlers.values)
        let gates = Array(connectionGates.values)
        lock.unlock()
        if case .disconnected = event {
            gates.forEach { $0.resetAfterDisconnect() }
        }
        handlers.forEach { $0(event) }
    }

    private func notify(_ event: MessagingRealtimeEvent, to id: UUID) {
        lock.lock()
        let handler = disconnectHandlers[id]
        let gate = connectionGates[id]
        lock.unlock()
        if case .disconnected = event {
            gate?.resetAfterDisconnect()
        }
        handler?(event)
    }
}

extension ParseMessagingLiveQueryClient: ParseLiveQueryDelegate {
    public func received(_ error: Error) {
        notify(.disconnected(errorDescription: String(describing: error)))
    }

    public func closedSocket(
        _ code: URLSessionWebSocketTask.CloseCode?,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
        let components = [code.map { "code=\($0.rawValue)" }, reasonText]
            .compactMap { $0 }
            .joined(separator: ", ")
        notify(.disconnected(errorDescription: components.isEmpty ? nil : components))
    }
}

private final class LiveQueryConnectionGate {
    private let expectedNames: Set<String>
    private let eventHandler: (MessagingRealtimeEvent) -> Void
    private let lock = NSLock()
    private var subscribedNames: Set<String> = []
    private var emittedConnected = false

    init(
        expectedSubscriptionNames: Set<String>,
        eventHandler: @escaping (MessagingRealtimeEvent) -> Void
    ) {
        expectedNames = expectedSubscriptionNames
        self.eventHandler = eventHandler
    }

    func didSubscribe(name: String) {
        lock.lock()
        subscribedNames.insert(name)
        let shouldEmit = !emittedConnected && subscribedNames == expectedNames
        if shouldEmit { emittedConnected = true }
        lock.unlock()
        if shouldEmit { eventHandler(.connected) }
    }

    func resetAfterDisconnect() {
        lock.lock()
        subscribedNames.removeAll()
        emittedConnected = false
        lock.unlock()
    }
}

private final class ParseMessagingLiveQueryToken: MessagingRealtimeSubscription {
    private let lock = NSLock()
    private var cancellations: [() -> Void] = []
    private var isCancelled = false

    func addCancellation(_ cancellation: @escaping () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            cancellation()
        } else {
            cancellations.append(cancellation)
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let work = cancellations
        cancellations.removeAll()
        lock.unlock()
        work.forEach { $0() }
    }

    deinit { cancel() }
}
