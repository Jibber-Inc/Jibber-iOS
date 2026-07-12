//
//  ParseMessagingManager.swift
//  Jibber
//
//  Parse-native messaging bootstrap and application-facing facade.
//

import Foundation
import MessagingContracts
import MessagingPersistence
import ParseCore
import ParseSwift
import UIKit

extension Notification.Name {
    static let parseMessagingDidChange = Notification.Name("parseMessagingDidChange")
    static let parseMessagingDidFail = Notification.Name("parseMessagingDidFail")
}

/// Owns the ParseSwift messaging session, user-scoped cache, realtime
/// subscriptions, and durable outbox. Presentation code should depend on this
/// facade instead of either Parse SDK directly.
@MainActor
final class ParseMessagingManager {

    static let shared = ParseMessagingManager()

    private(set) var authenticatedUserID: MessagingUserID?
    private(set) var store: GRDBMessagingStore?
    private(set) var repository: ParseMessagingRepository?

    var isInitialized: Bool {
        self.authenticatedUserID != nil && self.store != nil && self.repository != nil
    }

    private static var didInitializeParseSwift = false

    private var realtimeClient: ParseMessagingLiveQueryClient?
    private var realtimeSubscription: MessagingRealtimeSubscription?
    private var realtimeReconciler: MessagingRealtimeReconciler?
    private var outboxWorker: MessagingOutboxWorker?
    private var outboxPumpTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var isDrainingOutbox = false
    private var subscribedConversationIDs: Set<MessagingConversationID> = []
    private var realtimeCatchUpTracker = MessagingRealtimeCatchUpTracker()
    private var pendingTypingMutations: [String: MessagingMutation] = [:]
    private var typingMutationTasks: [String: Task<Void, Never>] = [:]
    private var typingMutationTokens: [String: UUID] = [:]
    private var foregroundObserver: NSObjectProtocol?

    private init() {
        self.foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isInitialized else { return }
                self.scheduleConversationRefresh()
                self.scheduleImmediateOutboxDrain()
            }
        }
    }

    func initialize(for user: User) async throws {
        guard let userID = user.objectId, !userID.isEmpty else {
            throw ParseMessagingManagerError.missingUserID
        }
        guard let sessionToken = user.sessionToken, !sessionToken.isEmpty else {
            throw ParseMessagingManagerError.missingSessionToken
        }

        if self.authenticatedUserID == userID, self.isInitialized {
            return
        }
        if self.isInitialized {
            await self.disconnect(clearCachedData: true)
        }

        try Self.initializeParseSwiftIfNeeded()
        let sessionProvider = LegacyParseMessagingSessionProvider(
            userID: userID,
            sessionToken: sessionToken
        )
        let authentication = MessagingAuthenticationCoordinator(
            sessionProvider: sessionProvider
        )
        guard try await authentication.synchronizeSession() == userID else {
            throw ParseMessagingManagerError.identityVerificationFailed
        }

        let databaseURL = try Self.databaseURL(for: userID)
        let store = try GRDBMessagingStore(databaseURL: databaseURL)
        let repository = ParseMessagingRepository(
            authenticatedUserID: userID,
            uploadCache: store
        )
        let capabilities = try await Self.resolveCapabilities(repository: repository)
        try Self.validate(capabilities: capabilities)
        let realtimeClient = try ParseMessagingLiveQueryClient(
            authenticatedUserID: userID
        )

        self.authenticatedUserID = userID
        self.store = store
        self.repository = repository
        self.realtimeClient = realtimeClient
        self.realtimeReconciler = MessagingRealtimeReconciler(store: store)
        self.outboxWorker = MessagingOutboxWorker(
            store: store,
            remote: repository,
            errorClassifier: ParseMessagingErrorClassifier()
        )

        do {
            try await self.refreshConversations()
            self.startOutboxPump()
        } catch {
            let classifier = ParseMessagingErrorClassifier()
            if classifier.isRetryableMessagingError(error) {
                let cachedIDs = try Self.cachedConversationIDs(in: store)
                try self.replaceRealtimeSubscription(conversationIDs: cachedIDs)
                self.startOutboxPump()
                self.postChange()
            } else {
                await self.disconnect(clearCachedData: false)
                throw error
            }
        }
    }

    func disconnect(clearCachedData: Bool = true) async {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.outboxPumpTask?.cancel()
        self.outboxPumpTask = nil
        self.realtimeSubscription?.cancel()
        self.realtimeSubscription = nil
        self.subscribedConversationIDs.removeAll()
        self.typingMutationTasks.values.forEach { $0.cancel() }
        self.typingMutationTasks.removeAll()
        self.typingMutationTokens.removeAll()
        self.pendingTypingMutations.removeAll()
        self.realtimeCatchUpTracker = MessagingRealtimeCatchUpTracker()

        if clearCachedData {
            try? self.store?.removeAllMessagingData()
        }

        self.outboxWorker = nil
        self.realtimeReconciler = nil
        self.realtimeClient = nil
        self.repository = nil
        self.store = nil
        self.authenticatedUserID = nil
        self.isDrainingOutbox = false
        try? await MessagingParseUser.logout()
    }

    // MARK: - Cached reads with remote refresh

    func conversations(
        before cursor: MessagingCursor? = nil,
        pageSize: Int = 50
    ) async throws -> MessagingPage<MessagingConversationSnapshot> {
        let components = try self.requireComponents()
        do {
            let page = try await components.repository.conversations(
                before: cursor,
                pageSize: pageSize
            )
            try components.store.upsert(conversations: page.items)
            return page
        } catch {
            try self.requireRetryableCacheFallback(after: error) {
                try components.store.removeAllMessagingData()
            }
            let cached = try components.store.cachedConversations(
                before: cursor,
                pageSize: pageSize
            )
            guard !cached.items.isEmpty else { throw error }
            return cached
        }
    }

    func messages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor? = nil,
        pageSize: Int = 50
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        let components = try self.requireComponents()
        do {
            let page = try await components.repository.messages(
                conversationID: conversationID,
                before: cursor,
                pageSize: pageSize
            )
            try components.store.upsert(messages: page.items)
            return page
        } catch {
            try self.requireRetryableCacheFallback(after: error) {
                try components.store.removeConversation(id: conversationID)
            }
            let cached = try components.store.cachedMessages(
                conversationID: conversationID,
                before: cursor,
                pageSize: pageSize
            )
            guard !cached.items.isEmpty else { throw error }
            return cached
        }
    }

    func replies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor? = nil,
        pageSize: Int = 50
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        let components = try self.requireComponents()
        do {
            let page = try await components.repository.replies(
                messageID: messageID,
                before: cursor,
                pageSize: pageSize
            )
            try components.store.upsert(messages: page.items)
            return page
        } catch {
            try self.requireRetryableCacheFallback(after: error) {
                if let root = try components.store.cachedMessage(objectID: messageID) {
                    try components.store.removeConversation(id: root.conversationID)
                } else {
                    try components.store.removeAllMessagingData()
                }
            }
            let cached = try components.store.cachedReplies(
                messageID: messageID,
                before: cursor,
                pageSize: pageSize
            )
            guard !cached.items.isEmpty else { throw error }
            return cached
        }
    }

    func pinnedMessages(
        conversationID: MessagingConversationID
    ) async throws -> [MessagingMessageSnapshot] {
        let components = try self.requireComponents()
        do {
            let messages = try await components.repository.pinnedMessages(
                conversationID: conversationID
            )
            try components.store.upsert(messages: messages)
            return messages
        } catch {
            try self.requireRetryableCacheFallback(after: error) {
                try components.store.removeConversation(id: conversationID)
            }
            let cached = try components.store.cachedPinnedMessages(
                conversationID: conversationID
            )
            guard !cached.isEmpty else { throw error }
            return cached
        }
    }

    func members(
        conversationID: MessagingConversationID
    ) async throws -> [MessagingMemberSnapshot] {
        let components = try self.requireComponents()
        do {
            let members = try await components.repository.members(
                conversationID: conversationID
            )
            try components.store.upsert(members: members)
            return members
        } catch {
            try self.requireRetryableCacheFallback(after: error) {
                try components.store.removeConversation(id: conversationID)
            }
            let cached = try components.store.cachedMembers(
                conversationID: conversationID
            )
            guard !cached.isEmpty else { throw error }
            return cached
        }
    }

    func members(
        conversationIDs: [MessagingConversationID]
    ) async throws -> [MessagingMemberSnapshot] {
        let components = try self.requireComponents()
        guard !conversationIDs.isEmpty else { return [] }
        do {
            let members = try await components.repository.members(
                conversationIDs: conversationIDs
            )
            try components.store.upsert(members: members)
            return members
        } catch {
            try self.requireRetryableCacheFallback(after: error) {
                for conversationID in conversationIDs {
                    try components.store.removeConversation(id: conversationID)
                }
            }
            let cached = try conversationIDs.flatMap {
                try components.store.cachedMembers(conversationID: $0)
            }
            guard !cached.isEmpty else { throw error }
            return cached
        }
    }

    // MARK: - Writes

    @discardableResult
    func createConversation(
        memberIDs: [MessagingUserID],
        type: MessagingConversationKind,
        title: String? = nil,
        clientConversationID: String = UUID().uuidString.lowercased(),
        contextKey: String? = nil
    ) async throws -> MessagingConversationSnapshot {
        let components = try self.requireComponents()
        let conversation = try await components.repository.createConversation(
            memberIDs: memberIDs,
            type: type,
            title: title,
            clientConversationID: clientConversationID,
            contextKey: contextKey
        )
        try components.store.upsert(conversations: [conversation])
        self.scheduleConversationRefresh()
        self.postChange()
        return conversation
    }

    /// Stages the optimistic message and its send operation atomically before
    /// any network work begins.
    @discardableResult
    func send(_ draft: MessagingMessageDraft) throws -> MessagingMessageSnapshot {
        let components = try self.requireComponents()
        guard let userID = self.authenticatedUserID else {
            throw ParseMessagingManagerError.notInitialized
        }
        let staged = try components.store.stageSend(draft: draft, authorID: userID)
        self.postChange()
        self.scheduleImmediateOutboxDrain()
        return staged.message
    }

    @discardableResult
    func enqueue(
        _ mutation: MessagingMutation,
        idempotencyKey: String = UUID().uuidString.lowercased()
    ) throws -> MessagingOutboxEntry {
        let components = try self.requireComponents()
        let entry = try components.store.enqueue(
            MessagingOutboxEntry(
                idempotencyKey: idempotencyKey,
                conversationID: mutation.conversationID,
                mutation: mutation
            )
        )
        self.scheduleImmediateOutboxDrain()
        return entry
    }

    /// Typing is presence, not durable user content. A single serial worker per
    /// membership sends the current value directly; heartbeats arriving while
    /// a request is in flight replace the pending value instead of joining the
    /// conversation FIFO.
    func setTypingBestEffort(
        conversationID: MessagingConversationID,
        memberID: String,
        expiresAt: Date?
    ) throws {
        _ = try self.requireComponents()
        let key = "\(conversationID):\(memberID)"
        self.pendingTypingMutations[key] = .setTyping(
            conversationID: conversationID,
            memberID: memberID,
            expiresAt: expiresAt
        )
        guard self.typingMutationTasks[key] == nil else { return }
        let token = UUID()
        self.typingMutationTokens[key] = token
        self.typingMutationTasks[key] = Task { @MainActor [weak self] in
            await self?.drainTypingMutations(for: key, token: token)
        }
    }

    @discardableResult
    func retryBlockedOperation(idempotencyKey: String) throws -> MessagingOutboxEntry {
        let components = try self.requireComponents()
        let entry = try components.store.retryBlockedOutboxEntry(
            idempotencyKey: idempotencyKey,
            at: Date()
        )
        self.postChange()
        self.scheduleImmediateOutboxDrain()
        return entry
    }

    func cancelBlockedOperation(idempotencyKey: String) throws {
        let components = try self.requireComponents()
        try components.store.cancelBlockedOutboxEntry(idempotencyKey: idempotencyKey)
        self.postChange()
        self.scheduleImmediateOutboxDrain()
    }

    // MARK: - Synchronization

    func refreshConversations() async throws {
        let components = try self.requireComponents()
        let cachedIDs = try Self.cachedConversationIDs(in: components.store)
        var activeIDs: Set<MessagingConversationID> = []
        var cursor: MessagingCursor?

        repeat {
            let page = try await components.repository.conversations(
                before: cursor,
                pageSize: 100
            )
            try components.store.upsert(conversations: page.items)
            activeIDs.formUnion(page.items.map(\.id))
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil

        for removedID in cachedIDs.subtracting(activeIDs) {
            try components.store.removeConversation(id: removedID)
        }

        try self.replaceRealtimeSubscription(conversationIDs: activeIDs)
        self.postChange()
    }

    private func replaceRealtimeSubscription(
        conversationIDs: Set<MessagingConversationID>
    ) throws {
        guard let realtimeClient = self.realtimeClient else {
            throw ParseMessagingManagerError.notInitialized
        }
        self.realtimeSubscription?.cancel()
        self.subscribedConversationIDs = conversationIDs
        self.realtimeSubscription = try realtimeClient.subscribe(
            conversationIDs: conversationIDs
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleRealtimeEvent(event)
            }
        }
    }

    private func handleRealtimeEvent(_ event: MessagingRealtimeEvent) {
        switch event {
        case .connected:
            if self.realtimeCatchUpTracker.consumeCatchUpOnConnected() {
                self.scheduleConversationRefresh()
            }
        case .conversationSetInvalidated:
            self.scheduleConversationRefresh()
        case .conversationUpserted(let conversation) where conversation.isDeleted:
            do {
                try self.store?.removeConversation(id: conversation.id)
                self.scheduleConversationRefresh()
                self.postChange()
            } catch {
                self.postFailure(error)
            }
        case .disconnected(let errorDescription):
            self.realtimeCatchUpTracker.disconnected()
            if let errorDescription = errorDescription {
                self.postFailure(ParseMessagingManagerError.realtimeDisconnected(errorDescription))
            }
        default:
            do {
                try self.realtimeReconciler?.apply(event)
                self.postChange()
            } catch {
                self.postFailure(error)
            }
        }
    }

    private func scheduleConversationRefresh() {
        guard self.refreshTask == nil else { return }
        self.refreshTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.refreshTask = nil }
            do {
                try await self.refreshConversations()
            } catch is CancellationError {
                return
            } catch {
                if ParseMessagingErrorClassifier().isRetryableMessagingError(error) {
                    self.realtimeCatchUpTracker.disconnected()
                }
                self.postFailure(error)
            }
        }
    }

    private func startOutboxPump() {
        self.outboxPumpTask?.cancel()
        self.outboxPumpTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.drainOutboxOnce()
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    return
                }
            }
        }
        self.scheduleImmediateOutboxDrain()
    }

    private func scheduleImmediateOutboxDrain() {
        Task { @MainActor [weak self] in
            await self?.drainOutboxOnce()
        }
    }

    private func drainOutboxOnce() async {
        guard !self.isDrainingOutbox, let worker = self.outboxWorker else { return }
        self.isDrainingOutbox = true
        defer { self.isDrainingOutbox = false }
        do {
            let report = try await worker.drainOnce()
            if report.succeeded > 0 || report.blocked > 0 || report.retryScheduled > 0 {
                self.postChange()
            }
        } catch is CancellationError {
            return
        } catch {
            self.postFailure(error)
        }
    }

    private func drainTypingMutations(for key: String, token: UUID) async {
        defer {
            if self.typingMutationTokens[key] == token {
                self.pendingTypingMutations[key] = nil
                self.typingMutationTasks[key] = nil
                self.typingMutationTokens[key] = nil
            }
        }
        while self.typingMutationTokens[key] == token,
              !Task.isCancelled,
              let mutation = self.pendingTypingMutations.removeValue(forKey: key) {
            guard let repository = self.repository else { return }
            do {
                let result = try await repository.perform(
                    mutation,
                    idempotencyKey: UUID().uuidString.lowercased()
                )
                if case .member(let member) = result {
                    try self.store?.upsert(members: [member])
                    self.postChange()
                }
            } catch is CancellationError {
                return
            } catch {
                let classifier = ParseMessagingErrorClassifier()
                if classifier.isMessagingAccessRevokedError(error) {
                    try? self.store?.removeConversation(id: mutation.conversationID)
                    self.postChange()
                    self.postFailure(error)
                } else if !classifier.isRetryableMessagingError(error) {
                    self.postFailure(error)
                }
            }
        }
    }

    // MARK: - Helpers

    private typealias Components = (
        store: GRDBMessagingStore,
        repository: ParseMessagingRepository
    )

    private func requireComponents() throws -> Components {
        guard let store = self.store, let repository = self.repository else {
            throw ParseMessagingManagerError.notInitialized
        }
        return (store, repository)
    }

    private func requireRetryableCacheFallback(
        after error: Error,
        purgeOnAccessRevoked: () throws -> Void
    ) throws {
        let classifier = ParseMessagingErrorClassifier()
        guard classifier.isRetryableMessagingError(error) else {
            if classifier.isMessagingAccessRevokedError(error) {
                try purgeOnAccessRevoked()
                self.postChange()
            }
            throw error
        }
    }

    private static func initializeParseSwiftIfNeeded() throws {
        guard !Self.didInitializeParseSwift else { return }
        guard let serverURL = URL(string: Config.shared.environment.url) else {
            throw ParseMessagingManagerError.invalidServerURL
        }
        ParseSwift.initialize(
            applicationId: Config.shared.environment.appId,
            clientKey: Config.shared.environment.clientKey,
            serverURL: serverURL,
            cacheMemoryCapacity: 32 * 1_024 * 1_024,
            cacheDiskCapacity: 128 * 1_024 * 1_024,
            httpAdditionalHeaders: [
                "X-Jibber-App-Version": Config.shared.appVersion,
                "X-Jibber-Messaging-Schema": String(MessagingCapabilities.supportedSchemaVersion)
            ]
        )
        Self.didInitializeParseSwift = true
    }

    private static func databaseURL(for userID: MessagingUserID) throws -> URL {
        let defaultURL = try GRDBMessagingStore.defaultDatabaseURL()
        let directoryName = Data(userID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return defaultURL
            .deletingLastPathComponent()
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("messaging.sqlite", isDirectory: false)
    }

    private static func validate(capabilities: MessagingCapabilities) throws {
        guard capabilities.available else {
            throw ParseMessagingManagerError.serviceUnavailable
        }
        guard capabilities.schemaVersion == MessagingCapabilities.supportedSchemaVersion else {
            throw ParseMessagingManagerError.unsupportedSchemaVersion(
                server: capabilities.schemaVersion,
                client: MessagingCapabilities.supportedSchemaVersion
            )
        }
        if let minimum = capabilities.minimumAppVersion,
           Self.compareVersions(Config.shared.appVersion, minimum) == .orderedAscending {
            throw ParseMessagingManagerError.appUpdateRequired(minimumVersion: minimum)
        }
    }

    private static func resolveCapabilities(
        repository: ParseMessagingRepository
    ) async throws -> MessagingCapabilities {
        do {
            let capabilities = try await repository.capabilities()
            if let data = try? JSONEncoder().encode(capabilities) {
                UserDefaults(suiteName: Config.shared.environment.groupId)?.set(
                    data,
                    forKey: "parseMessagingCapabilities"
                )
            }
            return capabilities
        } catch {
            let classifier = ParseMessagingErrorClassifier()
            guard classifier.isRetryableMessagingError(error),
                  let data = UserDefaults(
                    suiteName: Config.shared.environment.groupId
                  )?.data(forKey: "parseMessagingCapabilities"),
                  let cached = try? JSONDecoder().decode(
                    MessagingCapabilities.self,
                    from: data
                  ) else {
                throw error
            }
            return cached
        }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsParts.count, rhsParts.count)
        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func cachedConversationIDs(
        in store: GRDBMessagingStore
    ) throws -> Set<MessagingConversationID> {
        var ids: Set<MessagingConversationID> = []
        var cursor: MessagingCursor?
        repeat {
            let page = try store.cachedConversations(before: cursor, pageSize: 100)
            ids.formUnion(page.items.map(\.id))
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil
        return ids
    }

    private func postChange() {
        NotificationCenter.default.post(name: .parseMessagingDidChange, object: self)
    }

    private func postFailure(_ error: Error) {
        NotificationCenter.default.post(
            name: .parseMessagingDidFail,
            object: self,
            userInfo: ["error": error]
        )
        logError(error)
    }
}

private struct LegacyParseMessagingSessionProvider: MessagingSessionProviding {
    let userID: MessagingUserID
    let sessionToken: String

    func currentMessagingSession() throws -> MessagingAuthSession? {
        MessagingAuthSession(userID: self.userID, sessionToken: self.sessionToken)
    }
}

enum ParseMessagingManagerError: Error, LocalizedError {
    case appUpdateRequired(minimumVersion: String)
    case identityVerificationFailed
    case invalidServerURL
    case missingSessionToken
    case missingUserID
    case notInitialized
    case realtimeDisconnected(String)
    case serviceUnavailable
    case unsupportedSchemaVersion(server: Int, client: Int)

    var errorDescription: String? {
        switch self {
        case .appUpdateRequired(let minimumVersion):
            return "Jibber \(minimumVersion) or newer is required for messaging."
        case .identityVerificationFailed:
            return "Parse messaging authenticated a different user."
        case .invalidServerURL:
            return "The Parse messaging server URL is invalid."
        case .missingSessionToken:
            return "The current user has no Parse session token."
        case .missingUserID:
            return "The current user has no Parse object ID."
        case .notInitialized:
            return "Parse messaging has not been initialized."
        case .realtimeDisconnected(let detail):
            return "Parse messaging realtime disconnected: \(detail)"
        case .serviceUnavailable:
            return "Parse messaging is temporarily unavailable."
        case .unsupportedSchemaVersion(let server, let client):
            return "Messaging schema mismatch (server \(server), client \(client))."
        }
    }
}
