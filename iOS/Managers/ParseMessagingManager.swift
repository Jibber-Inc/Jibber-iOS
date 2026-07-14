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

private enum ParseMessagingNotificationKey {
    static let conversationIDs = "conversationIDs"
}

private actor ParseMessagingLifecycleGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard self.isLocked else {
            self.isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
        }
    }

    func release() {
        guard !self.waiters.isEmpty else {
            self.isLocked = false
            return
        }
        self.waiters.removeFirst().resume()
    }
}

extension Notification {
    /// `nil` means the cache changed globally. A non-nil set lets retained
    /// controllers ignore work for conversations they do not present.
    var parseMessagingConversationIDs: Set<MessagingConversationID>? {
        self.userInfo?[ParseMessagingNotificationKey.conversationIDs]
            as? Set<MessagingConversationID>
    }

    func affectsMessagingConversation(_ conversationID: MessagingConversationID) -> Bool {
        self.parseMessagingConversationIDs?.contains(conversationID) ?? true
    }
}

/// LiveQuery callbacks arrive on the presentation facade, but GRDB
/// reconciliation must never occupy the main actor. The actor also preserves
/// event ordering while the shared DatabaseQueue serializes its transactions.
private actor ParseMessagingRealtimeProcessor {
    private let store: GRDBMessagingStore
    private let reconciler: MessagingRealtimeReconciler
    private var isValid = true

    init(store: GRDBMessagingStore) {
        self.store = store
        self.reconciler = MessagingRealtimeReconciler(store: store)
    }

    func apply(
        _ event: MessagingRealtimeEvent
    ) throws -> Set<MessagingConversationID> {
        guard self.isValid else { throw CancellationError() }
        try self.reconciler.apply(event)
        switch event {
        case .conversationUpserted(let conversation):
            return [conversation.id]
        case .memberUpserted(let member):
            return [member.conversationID]
        case .messageUpserted(let message), .messageDeleted(let message):
            return [message.conversationID]
        case .reactionUpserted(let reaction):
            return try self.store.cachedMessage(objectID: reaction.messageID)
                .map { [$0.conversationID] } ?? []
        case .receiptUpserted(let receipt):
            return try self.store.cachedMessage(objectID: receipt.messageID)
                .map { [$0.conversationID] } ?? []
        case .conversationSetInvalidated(let conversationID):
            return [conversationID]
        case .connected, .disconnected:
            return []
        }
    }

    func removeConversation(id: MessagingConversationID) throws {
        guard self.isValid else { throw CancellationError() }
        try self.store.removeConversation(id: id)
    }

    func invalidate() {
        self.isValid = false
    }
}

/// Keeps synchronous GRDB APIs off the main actor while preserving the
/// ordering of cache mutations issued by the presentation facade.
private actor ParseMessagingStorage {
    private let store: GRDBMessagingStore
    private var isValid = true

    init(store: GRDBMessagingStore) {
        self.store = store
    }

    func upsert(conversations: [MessagingConversationSnapshot]) throws {
        try self.requireValid()
        try self.store.upsert(conversations: conversations)
    }

    func upsert(messages: [MessagingMessageSnapshot]) throws {
        try self.requireValid()
        try self.store.upsert(messages: messages)
    }

    func upsert(members: [MessagingMemberSnapshot]) throws {
        try self.requireValid()
        try self.store.upsert(members: members)
    }

    func cachedConversations(
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> MessagingPage<MessagingConversationSnapshot> {
        try self.requireValid()
        return try self.store.cachedConversations(before: cursor, pageSize: pageSize)
    }

    func cachedConversations(
        ids: [MessagingConversationID]
    ) throws -> [MessagingConversationSnapshot] {
        try self.requireValid()
        return try ids.compactMap { try self.store.cachedConversation(id: $0) }
    }

    func cachedMessages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> MessagingPage<MessagingMessageSnapshot> {
        try self.requireValid()
        return try self.store.cachedMessages(
            conversationID: conversationID,
            before: cursor,
            pageSize: pageSize
        )
    }

    func cachedMessages(
        ids: [MessagingMessageID]
    ) throws -> [MessagingMessageSnapshot] {
        try self.requireValid()
        return try self.store.cachedMessages(ids: ids)
    }

    func cachedReplies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> MessagingPage<MessagingMessageSnapshot> {
        try self.requireValid()
        return try self.store.cachedReplies(
            messageID: messageID,
            before: cursor,
            pageSize: pageSize
        )
    }

    func cachedReplyPreview(
        messageID: MessagingMessageID,
        latestReplyID: MessagingMessageID?
    ) throws -> [MessagingMessageSnapshot] {
        try self.requireValid()
        return try self.store.cachedReplyPreview(
            messageID: messageID,
            latestReplyID: latestReplyID
        )
    }

    func cachedPinnedMessages(
        conversationID: MessagingConversationID
    ) throws -> [MessagingMessageSnapshot] {
        try self.requireValid()
        return try self.store.cachedPinnedMessages(conversationID: conversationID)
    }

    func cachedMembers(
        conversationID: MessagingConversationID
    ) throws -> [MessagingMemberSnapshot] {
        try self.requireValid()
        return try self.store.cachedMembers(conversationID: conversationID)
    }

    func cachedMembers(
        conversationIDs: [MessagingConversationID]
    ) throws -> [MessagingMemberSnapshot] {
        try self.requireValid()
        return try conversationIDs.flatMap {
            try self.store.cachedMembers(conversationID: $0)
        }
    }

    func cachedConversationIDs() throws -> Set<MessagingConversationID> {
        try self.requireValid()
        var ids: Set<MessagingConversationID> = []
        var cursor: MessagingCursor?
        repeat {
            let page = try self.store.cachedConversations(before: cursor, pageSize: 100)
            ids.formUnion(page.items.map(\.id))
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil
        return ids
    }

    func cachedConversationState(
        conversationID: MessagingConversationID,
        pageSize: Int
    ) async throws -> MessagingConversationCacheState {
        try self.requireValid()
        let state = try await self.store.cachedConversationState(
            conversationID: conversationID,
            pageSize: pageSize
        )
        try self.requireValid()
        return state
    }

    func cachedMessage(id: MessagingMessageID) throws -> MessagingMessageSnapshot? {
        try self.requireValid()
        return try self.store.cachedMessage(objectID: id)
            ?? self.store.cachedMessage(clientMessageID: id)
    }

    func stageSend(
        draft: MessagingMessageDraft,
        authorID: MessagingUserID
    ) throws -> (message: MessagingMessageSnapshot, entry: MessagingOutboxEntry) {
        try self.requireValid()
        return try self.store.stageSend(draft: draft, authorID: authorID)
    }

    func enqueue(_ entry: MessagingOutboxEntry) throws -> MessagingOutboxEntry {
        try self.requireValid()
        return try self.store.enqueue(entry)
    }

    func retryBlockedOutboxEntry(
        idempotencyKey: String,
        at date: Date
    ) throws -> MessagingOutboxEntry {
        try self.requireValid()
        return try self.store.retryBlockedOutboxEntry(
            idempotencyKey: idempotencyKey,
            at: date
        )
    }

    func cancelBlockedOutboxEntry(idempotencyKey: String) throws {
        try self.requireValid()
        try self.store.cancelBlockedOutboxEntry(idempotencyKey: idempotencyKey)
    }

    func removeConversation(id: MessagingConversationID) throws {
        try self.requireValid()
        try self.store.removeConversation(id: id)
    }

    func removeConversations(ids: Set<MessagingConversationID>) throws {
        try self.requireValid()
        for id in ids {
            try self.store.removeConversation(id: id)
        }
    }

    func removeConversation(containingMessageID messageID: MessagingMessageID) throws {
        try self.requireValid()
        if let root = try self.store.cachedMessage(objectID: messageID) {
            try self.store.removeConversation(id: root.conversationID)
        } else {
            try self.store.removeAllMessagingData()
        }
    }

    func removeAllMessagingData() throws {
        try self.requireValid()
        try self.store.removeAllMessagingData()
    }

    func invalidate(clearCachedData: Bool) throws {
        self.isValid = false
        if clearCachedData {
            try self.store.removeAllMessagingData()
        }
    }

    private func requireValid() throws {
        guard self.isValid else { throw CancellationError() }
    }
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
        self.authenticatedUserID != nil
            && self.store != nil
            && self.repository != nil
            && self.storage != nil
            && self.sessionIdentity != nil
            && self.sessionIdentity == self.lifecycleIdentity
    }

    private static var didInitializeParseSwift = false

    private let lifecycleGate = ParseMessagingLifecycleGate()
    private var lifecycleIdentity = UUID()
    private var realtimeClient: ParseMessagingLiveQueryClient?
    private var realtimeSubscription: MessagingRealtimeSubscription?
    private var realtimeProcessor: ParseMessagingRealtimeProcessor?
    private var storage: ParseMessagingStorage?
    private var sessionIdentity: UUID?
    private var outboxWorker: MessagingOutboxWorker?
    private var outboxPumpTask: Task<Void, Never>?
    private var outboxDrainTask: Task<Void, Never>?
    private var outboxDrainToken: UUID?
    private var isOutboxDrainRequested = false
    private var refreshTask: Task<Void, Never>?
    private var refreshTaskToken: UUID?
    private var latestReplyHydrationTask: Task<Void, Never>?
    private var latestReplyHydrationToken: UUID?
    private var pendingLatestReplyRoots: [MessagingMessageID: MessagingMessageSnapshot] = [:]
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
                guard let self else { return }
                guard self.isInitialized else { return }
                self.scheduleConversationRefresh()
                self.scheduleImmediateOutboxDrain()
            }
        }
    }

    func initialize(for user: User) async throws {
        await self.lifecycleGate.acquire()
        do {
            try await self.initializeHoldingLifecycleGate(for: user)
            await self.lifecycleGate.release()
        } catch {
            await self.lifecycleGate.release()
            throw error
        }
    }

    private func initializeHoldingLifecycleGate(for user: User) async throws {
        guard let userID = user.objectId, !userID.isEmpty else {
            throw ParseMessagingManagerError.missingUserID
        }
        guard let sessionToken = user.sessionToken, !sessionToken.isEmpty else {
            throw ParseMessagingManagerError.missingSessionToken
        }

        if self.authenticatedUserID == userID, self.isInitialized {
            return
        }
        if self.authenticatedUserID != nil
            || self.store != nil
            || self.repository != nil
            || self.storage != nil {
            await self.disconnectHoldingLifecycleGate(clearCachedData: true)
        }

        let initializationIdentity = UUID()
        self.lifecycleIdentity = initializationIdentity

        try Self.initializeParseSwiftIfNeeded()
        let sessionProvider = LegacyParseMessagingSessionProvider(
            userID: userID,
            sessionToken: sessionToken
        )
        let authentication = MessagingAuthenticationCoordinator(
            sessionProvider: sessionProvider
        )
        let synchronizedUserID = try await authentication.synchronizeSession()
        try self.validateLifecycle(identity: initializationIdentity)
        guard synchronizedUserID == userID else {
            throw ParseMessagingManagerError.identityVerificationFailed
        }

        let databaseURL = try Self.databaseURL(for: userID)
        let store = try await Self.makeStore(databaseURL: databaseURL)
        try self.validateLifecycle(identity: initializationIdentity)
        let repository = ParseMessagingRepository(
            authenticatedUserID: userID,
            uploadCache: store
        )
        let capabilities = try await Self.resolveCapabilities(repository: repository)
        try self.validateLifecycle(identity: initializationIdentity)
        try Self.validate(capabilities: capabilities)
        let realtimeClient = try ParseMessagingLiveQueryClient(
            authenticatedUserID: userID
        )

        self.authenticatedUserID = userID
        self.store = store
        self.repository = repository
        self.realtimeClient = realtimeClient
        self.realtimeProcessor = ParseMessagingRealtimeProcessor(store: store)
        self.storage = ParseMessagingStorage(store: store)
        self.sessionIdentity = initializationIdentity
        self.outboxWorker = MessagingOutboxWorker(
            store: store,
            remote: repository,
            errorClassifier: ParseMessagingErrorClassifier()
        )

        do {
            try await self.refreshConversations()
            self.startOutboxPump()
        } catch {
            guard self.lifecycleIdentity == initializationIdentity,
                  self.sessionIdentity == initializationIdentity else {
                throw CancellationError()
            }
            let classifier = ParseMessagingErrorClassifier()
            if classifier.isRetryableMessagingError(error) {
                let components = try self.requireComponents()
                let cachedIDs = try await components.storage.cachedConversationIDs()
                try self.validateCurrentSession(components)
                try self.replaceRealtimeSubscription(conversationIDs: cachedIDs)
                self.startOutboxPump()
                self.postChange()
            } else {
                await self.disconnectHoldingLifecycleGate(clearCachedData: false)
                throw error
            }
        }
    }

    func disconnect(clearCachedData: Bool = true) async {
        await self.lifecycleGate.acquire()
        await self.disconnectHoldingLifecycleGate(clearCachedData: clearCachedData)
        await self.lifecycleGate.release()
    }

    private func disconnectHoldingLifecycleGate(clearCachedData: Bool) async {
        self.lifecycleIdentity = UUID()
        let storage = self.storage
        let realtimeProcessor = self.realtimeProcessor
        let outboxWorker = self.outboxWorker
        let refreshTask = self.refreshTask
        let latestReplyHydrationTask = self.latestReplyHydrationTask
        let outboxPumpTask = self.outboxPumpTask
        let outboxDrainTask = self.outboxDrainTask
        let typingMutationTasks = Array(self.typingMutationTasks.values)
        self.sessionIdentity = nil
        outboxWorker?.invalidate()
        refreshTask?.cancel()
        latestReplyHydrationTask?.cancel()
        outboxPumpTask?.cancel()
        outboxDrainTask?.cancel()
        typingMutationTasks.forEach { $0.cancel() }
        self.realtimeSubscription?.cancel()

        self.refreshTask = nil
        self.refreshTaskToken = nil
        self.latestReplyHydrationTask = nil
        self.latestReplyHydrationToken = nil
        self.pendingLatestReplyRoots.removeAll()
        self.outboxPumpTask = nil
        self.outboxDrainTask = nil
        self.outboxDrainToken = nil
        self.isOutboxDrainRequested = false
        self.realtimeSubscription = nil
        self.subscribedConversationIDs.removeAll()
        self.typingMutationTasks.removeAll()
        self.typingMutationTokens.removeAll()
        self.pendingTypingMutations.removeAll()
        self.realtimeCatchUpTracker = MessagingRealtimeCatchUpTracker()
        self.outboxWorker = nil
        self.realtimeProcessor = nil
        self.storage = nil
        self.realtimeClient = nil
        self.repository = nil
        self.store = nil
        self.authenticatedUserID = nil
        self.isDrainingOutbox = false

        // ParseSwift bridges callback URLSession requests with continuations,
        // so canceling their Swift Tasks does not make those continuations
        // resume. Do not hold the lifecycle gate waiting for network timeouts.
        // Session identity checks stop manager tasks before future writes, and
        // worker invalidation provides the same fence inside an in-flight
        // outbox drain. Actor invalidation below is bounded to synchronous GRDB
        // work and is ordered before an optional purge.
        await realtimeProcessor?.invalidate()
        try? await storage?.invalidate(clearCachedData: clearCachedData)

        // The Objective-C Parse logout remains the owner of server-session
        // invalidation. An asynchronous ParseSwift logout can finish after a
        // subsequent `become` and erase the new user's keychain session; the
        // next manager initialization safely replaces this detached session.
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
            try self.validateCurrentSession(components)
            try await components.storage.upsert(conversations: page.items)
            try self.validateCurrentSession(components)
            let reconciled = try await components.storage.cachedConversations(
                ids: page.items.map(\.id)
            )
            try self.validateCurrentSession(components)
            return MessagingPage(
                items: Self.reconciledConversationPageItems(
                    remote: page.items,
                    cached: reconciled
                ),
                nextCursor: page.nextCursor,
                hasMore: page.hasMore
            )
        } catch {
            try await self.requireRetryableCacheFallback(after: error, components: components) {
                try await components.storage.removeAllMessagingData()
            }
            try self.validateCurrentSession(components)
            let cached = try await components.storage.cachedConversations(
                before: cursor,
                pageSize: pageSize
            )
            try self.validateCurrentSession(components)
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
            try self.validateCurrentSession(components)
            try await components.storage.upsert(messages: page.items)
            try self.validateCurrentSession(components)
            do {
                let latestReplies = try await components.repository.latestReplies(
                    for: page.items
                )
                try self.validateCurrentSession(components)
                try await components.storage.upsert(messages: latestReplies)
                try self.validateCurrentSession(components)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Full preview objects are supplemental to an otherwise valid
                // root page. Keep the page usable and retry hydration on the
                // next page/root LiveQuery refresh.
                try self.validateCurrentSession(components)
                self.postFailure(error)
            }
            try self.validateCurrentSession(components)
            let reconciled = try await components.storage.cachedMessages(
                ids: page.items.map { $0.objectID ?? $0.stableID }
            )
            try self.validateCurrentSession(components)
            return MessagingPage(
                items: Self.reconciledPageItems(
                    remote: page.items,
                    cached: reconciled
                ),
                nextCursor: page.nextCursor,
                hasMore: page.hasMore
            )
        } catch {
            try await self.requireRetryableCacheFallback(after: error, components: components) {
                try await components.storage.removeConversation(id: conversationID)
            }
            try self.validateCurrentSession(components)
            let cached = try await components.storage.cachedMessages(
                conversationID: conversationID,
                before: cursor,
                pageSize: pageSize
            )
            try self.validateCurrentSession(components)
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
            try self.validateCurrentSession(components)
            try await components.storage.upsert(messages: page.items)
            try self.validateCurrentSession(components)
            let reconciled = try await components.storage.cachedMessages(
                ids: page.items.map { $0.objectID ?? $0.stableID }
            )
            try self.validateCurrentSession(components)
            return MessagingPage(
                items: Self.reconciledPageItems(
                    remote: page.items,
                    cached: reconciled
                ),
                nextCursor: page.nextCursor,
                hasMore: page.hasMore
            )
        } catch {
            try await self.requireRetryableCacheFallback(after: error, components: components) {
                try await components.storage.removeConversation(containingMessageID: messageID)
            }
            try self.validateCurrentSession(components)
            let cached = try await components.storage.cachedReplies(
                messageID: messageID,
                before: cursor,
                pageSize: pageSize
            )
            try self.validateCurrentSession(components)
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
            try self.validateCurrentSession(components)
            try await components.storage.upsert(messages: messages)
            try self.validateCurrentSession(components)
            let reconciled = try await components.storage.cachedPinnedMessages(
                conversationID: conversationID
            )
            try self.validateCurrentSession(components)
            return reconciled
        } catch {
            try await self.requireRetryableCacheFallback(after: error, components: components) {
                try await components.storage.removeConversation(id: conversationID)
            }
            try self.validateCurrentSession(components)
            let cached = try await components.storage.cachedPinnedMessages(
                conversationID: conversationID
            )
            try self.validateCurrentSession(components)
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
            try self.validateCurrentSession(components)
            try await components.storage.upsert(members: members)
            try self.validateCurrentSession(components)
            let reconciled = try await components.storage.cachedMembers(
                conversationID: conversationID
            )
            try self.validateCurrentSession(components)
            let changedConversationIDs = Set(members.map(\.conversationID))
            if !changedConversationIDs.isEmpty {
                self.postChange(conversationIDs: changedConversationIDs)
            }
            return reconciled
        } catch {
            try await self.requireRetryableCacheFallback(after: error, components: components) {
                try await components.storage.removeConversation(id: conversationID)
            }
            try self.validateCurrentSession(components)
            let cached = try await components.storage.cachedMembers(
                conversationID: conversationID
            )
            try self.validateCurrentSession(components)
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
            try self.validateCurrentSession(components)
            try await components.storage.upsert(members: members)
            try self.validateCurrentSession(components)
            let reconciled = try await components.storage.cachedMembers(
                conversationIDs: conversationIDs
            )
            try self.validateCurrentSession(components)
            // A conversation-list refresh can hydrate membership while a
            // retained conversation controller is already on screen. Publish
            // the scoped cache change so that controller reloads authoritative
            // unread/read-boundary state instead of waiting for LiveQuery.
            let changedConversationIDs = Set(members.map(\.conversationID))
            if !changedConversationIDs.isEmpty {
                self.postChange(conversationIDs: changedConversationIDs)
            }
            return reconciled
        } catch {
            try await self.requireRetryableCacheFallback(after: error, components: components) {
                try await components.storage.removeConversations(ids: Set(conversationIDs))
            }
            try self.validateCurrentSession(components)
            let cached = try await components.storage.cachedMembers(
                conversationIDs: conversationIDs
            )
            try self.validateCurrentSession(components)
            guard !cached.isEmpty else { throw error }
            return cached
        }
    }

    /// Returns one transactionally consistent cache snapshot for legacy
    /// presentation code without doing GRDB reads or decoding on MainActor.
    func cachedConversationState(
        conversationID: MessagingConversationID,
        pageSize: Int = 100
    ) async throws -> MessagingConversationCacheState {
        let components = try self.requireComponents()
        let state = try await components.storage.cachedConversationState(
            conversationID: conversationID,
            pageSize: pageSize
        )
        try self.validateCurrentSession(components)
        return state
    }

    /// Resolves either a server object ID or an optimistic client ID while
    /// enforcing both conversation and current-session identity.
    func cachedMessage(
        conversationID: MessagingConversationID,
        id: MessagingMessageID
    ) async throws -> MessagingMessageSnapshot? {
        let components = try self.requireComponents()
        let message = try await components.storage.cachedMessage(id: id)
        try self.validateCurrentSession(components)
        guard message?.conversationID == conversationID else { return nil }
        return message
    }

    /// Cache-only visible-cell input: the exact server-selected reply plus
    /// any optimistic replies staged by another controller.
    func cachedReplyPreview(
        conversationID: MessagingConversationID,
        messageID: MessagingMessageID,
        latestReplyID: MessagingMessageID?
    ) async throws -> [MessagingMessageSnapshot] {
        let components = try self.requireComponents()
        let messages = try await components.storage.cachedReplyPreview(
            messageID: messageID,
            latestReplyID: latestReplyID
        )
        try self.validateCurrentSession(components)
        return messages.filter { $0.conversationID == conversationID }
    }

    /// Preserve the exact remote page cardinality/cursor contract while using
    /// freshness-reconciled cache values wherever retained. An incoming page
    /// older than the local 2,000-message retention window is pruned during
    /// upsert; those deliberate cache misses must still be returned or the
    /// remote cursor would skip history forever.
    private static func reconciledPageItems(
        remote: [MessagingMessageSnapshot],
        cached: [MessagingMessageSnapshot]
    ) -> [MessagingMessageSnapshot] {
        var cachedByID: [MessagingMessageID: MessagingMessageSnapshot] = [:]
        cachedByID.reserveCapacity(cached.count * 2)
        for message in cached {
            cachedByID[message.stableID] = message
            if let objectID = message.objectID {
                cachedByID[objectID] = message
            }
        }
        return remote.map { message in
            if let objectID = message.objectID,
               let reconciled = cachedByID[objectID] {
                return reconciled
            }
            return cachedByID[message.stableID] ?? message
        }
    }

    private static func reconciledConversationPageItems(
        remote: [MessagingConversationSnapshot],
        cached: [MessagingConversationSnapshot]
    ) -> [MessagingConversationSnapshot] {
        let cachedByID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        return remote.map { cachedByID[$0.id] ?? $0 }
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
        try self.validateCurrentSession(components)
        try await components.storage.upsert(conversations: [conversation])
        try self.validateCurrentSession(components)
        self.scheduleConversationRefresh()
        self.postChange(conversationIDs: [conversation.id])
        return conversation
    }

    /// Allows compatibility controllers that fetched through a captured
    /// repository/store pair to cache the result without blocking the main
    /// actor or crossing into a replacement user session.
    func upsertConversation(
        _ conversation: MessagingConversationSnapshot,
        expectedStore: GRDBMessagingStore
    ) async throws {
        let components = try self.requireComponents()
        guard components.store === expectedStore else {
            throw CancellationError()
        }
        try await components.storage.upsert(conversations: [conversation])
        try self.validateCurrentSession(components)
    }

    /// Stages the optimistic message and its send operation atomically before
    /// any network work begins.
    @discardableResult
    func send(
        _ draft: MessagingMessageDraft,
        expectedStore: GRDBMessagingStore? = nil,
        expectedUserID: MessagingUserID? = nil
    ) async throws -> MessagingMessageSnapshot {
        let components = try self.requireComponents()
        if let expectedStore, components.store !== expectedStore {
            throw CancellationError()
        }
        if let expectedUserID, components.userID != expectedUserID {
            throw CancellationError()
        }
        let staged = try await components.storage.stageSend(
            draft: draft,
            authorID: components.userID
        )
        try self.validateCurrentSession(components)
        self.postChange(conversationIDs: [draft.conversationID])
        self.scheduleImmediateOutboxDrain()
        return staged.message
    }

    @discardableResult
    func enqueue(
        _ mutation: MessagingMutation,
        idempotencyKey: String = UUID().uuidString.lowercased(),
        expectedStore: GRDBMessagingStore? = nil,
        expectedUserID: MessagingUserID? = nil
    ) async throws -> MessagingOutboxEntry {
        let components = try self.requireComponents()
        if let expectedStore, components.store !== expectedStore {
            throw CancellationError()
        }
        if let expectedUserID, components.userID != expectedUserID {
            throw CancellationError()
        }
        let entry = try await components.storage.enqueue(
            MessagingOutboxEntry(
                idempotencyKey: idempotencyKey,
                conversationID: mutation.conversationID,
                mutation: mutation,
                actorID: components.userID
            )
        )
        try self.validateCurrentSession(components)
        self.postChange(conversationIDs: [mutation.conversationID])
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
    func retryBlockedOperation(idempotencyKey: String) async throws -> MessagingOutboxEntry {
        let components = try self.requireComponents()
        let entry = try await components.storage.retryBlockedOutboxEntry(
            idempotencyKey: idempotencyKey,
            at: Date()
        )
        try self.validateCurrentSession(components)
        self.postChange(conversationIDs: [entry.conversationID])
        self.scheduleImmediateOutboxDrain()
        return entry
    }

    func cancelBlockedOperation(idempotencyKey: String) async throws {
        let components = try self.requireComponents()
        try await components.storage.cancelBlockedOutboxEntry(
            idempotencyKey: idempotencyKey
        )
        try self.validateCurrentSession(components)
        self.postChange()
        self.scheduleImmediateOutboxDrain()
    }

    // MARK: - Synchronization

    func refreshConversations() async throws {
        let components = try self.requireComponents()
        let cachedIDs = try await components.storage.cachedConversationIDs()
        try self.validateCurrentSession(components)
        var activeIDs: Set<MessagingConversationID> = []
        var cursor: MessagingCursor?

        repeat {
            let page = try await components.repository.conversations(
                before: cursor,
                pageSize: 100
            )
            try self.validateCurrentSession(components)
            try await components.storage.upsert(conversations: page.items)
            try self.validateCurrentSession(components)
            activeIDs.formUnion(page.items.map(\.id))
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil

        try await components.storage.removeConversations(ids: cachedIDs.subtracting(activeIDs))
        try self.validateCurrentSession(components)

        try self.replaceRealtimeSubscription(conversationIDs: activeIDs)
        self.postChange()
    }

    private func replaceRealtimeSubscription(
        conversationIDs: Set<MessagingConversationID>
    ) throws {
        guard let realtimeClient = self.realtimeClient else {
            throw ParseMessagingManagerError.notInitialized
        }
        guard let sessionIdentity = self.sessionIdentity else {
            throw ParseMessagingManagerError.notInitialized
        }
        self.realtimeSubscription?.cancel()
        self.subscribedConversationIDs = conversationIDs
        self.realtimeSubscription = try realtimeClient.subscribe(
            conversationIDs: conversationIDs
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                await self?.handleRealtimeEvent(event, sessionIdentity: sessionIdentity)
            }
        }
    }

    private func handleRealtimeEvent(
        _ event: MessagingRealtimeEvent,
        sessionIdentity: UUID
    ) async {
        guard self.sessionIdentity == sessionIdentity else { return }
        switch event {
        case .connected:
            if self.realtimeCatchUpTracker.consumeCatchUpOnConnected() {
                self.scheduleConversationRefresh()
            }
        case .conversationSetInvalidated:
            self.scheduleConversationRefresh()
        case .conversationUpserted(let conversation) where conversation.isDeleted:
            guard let processor = self.realtimeProcessor else { return }
            do {
                try await processor.removeConversation(id: conversation.id)
                guard self.sessionIdentity == sessionIdentity,
                      self.realtimeProcessor === processor else { return }
                self.scheduleConversationRefresh()
                self.postChange(conversationIDs: [conversation.id])
            } catch {
                guard self.sessionIdentity == sessionIdentity,
                      self.realtimeProcessor === processor else { return }
                self.postFailure(error)
            }
        case .disconnected(let errorDescription):
            self.realtimeCatchUpTracker.disconnected()
            if let errorDescription = errorDescription {
                self.postFailure(ParseMessagingManagerError.realtimeDisconnected(errorDescription))
            }
        default:
            guard let processor = self.realtimeProcessor else { return }
            do {
                let conversationIDs = try await processor.apply(event)
                guard self.sessionIdentity == sessionIdentity,
                      self.realtimeProcessor === processor else { return }
                guard !conversationIDs.isEmpty else { return }
                if case .messageUpserted(let message) = event,
                   message.replyToMessageID == nil {
                    let components = try self.requireComponents()
                    let reconciledRoot = try await components.storage.cachedMessage(
                        id: message.canonicalMessageID
                    )
                    try self.validateCurrentSession(components)
                    if let reconciledRoot, reconciledRoot.replyToMessageID == nil {
                        self.scheduleLatestReplyHydration(for: reconciledRoot)
                    }
                }
                self.postChange(conversationIDs: conversationIDs)
            } catch {
                guard self.sessionIdentity == sessionIdentity,
                      self.realtimeProcessor === processor else { return }
                self.postFailure(error)
            }
        }
    }

    private func scheduleConversationRefresh() {
        guard self.refreshTask == nil else { return }
        let token = UUID()
        self.refreshTaskToken = token
        self.refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.refreshTaskToken == token {
                    self.refreshTask = nil
                    self.refreshTaskToken = nil
                }
            }
            do {
                try await self.refreshConversations()
            } catch is CancellationError {
                return
            } catch {
                guard self.refreshTaskToken == token else { return }
                if ParseMessagingErrorClassifier().isRetryableMessagingError(error) {
                    self.realtimeCatchUpTracker.disconnected()
                }
                self.postFailure(error)
            }
        }
    }

    /// Root summary pointers can move backward when the newest reply is
    /// deleted. The newly selected older object emits no LiveQuery event of
    /// its own, so coalesce root updates into one background pointer batch and
    /// persist any missing replies before notifying cache consumers again.
    private func scheduleLatestReplyHydration(
        for root: MessagingMessageSnapshot
    ) {
        guard root.replyToMessageID == nil,
              root.latestReplyID != nil,
              self.sessionIdentity != nil else { return }

        self.pendingLatestReplyRoots[root.canonicalMessageID] = root
        guard self.latestReplyHydrationTask == nil else { return }

        let token = UUID()
        self.latestReplyHydrationToken = token
        self.latestReplyHydrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.latestReplyHydrationToken == token {
                    self.latestReplyHydrationTask = nil
                    self.latestReplyHydrationToken = nil
                }
            }

            while !Task.isCancelled,
                  self.latestReplyHydrationToken == token,
                  !self.pendingLatestReplyRoots.isEmpty {
                await Task.yield()
                let roots = Array(self.pendingLatestReplyRoots.values)
                self.pendingLatestReplyRoots.removeAll(keepingCapacity: true)

                do {
                    let components = try self.requireComponents()
                    let latestReplyIDs = ParseMessagingReplyPreviewBatch
                        .latestReplyIDs(in: roots)
                    let cachedReplies = try await components.storage.cachedMessages(
                        ids: latestReplyIDs
                    )
                    try self.validateCurrentSession(components)
                    let cachedRepliesByID = Dictionary(
                        uniqueKeysWithValues: cachedReplies.compactMap { reply in
                            reply.objectID.map { ($0, reply) }
                        }
                    )
                    let rootsNeedingHydration = roots.filter { root in
                        guard let latestReplyID = root.latestReplyID,
                              let reply = cachedRepliesByID[latestReplyID] else { return true }
                        let belongsToRoot = reply.replyToMessageID == root.objectID
                            || reply.replyToMessageID == root.stableID
                        return !belongsToRoot
                            || reply.conversationID != root.conversationID
                            || !reply.isActiveForReplySummary
                    }
                    guard !rootsNeedingHydration.isEmpty else { continue }

                    let latestReplies = try await components.repository.latestReplies(
                        for: rootsNeedingHydration
                    )
                    try self.validateCurrentSession(components)
                    try await components.storage.upsert(messages: latestReplies)
                    try self.validateCurrentSession(components)
                    self.postChange(
                        conversationIDs: Set(rootsNeedingHydration.map(\.conversationID))
                    )
                } catch is CancellationError {
                    return
                } catch {
                    self.postFailure(error)
                }
            }
        }
    }

    private func startOutboxPump() {
        self.outboxPumpTask?.cancel()
        self.outboxPumpTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.scheduleImmediateOutboxDrain()
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
        self.isOutboxDrainRequested = true
        guard self.outboxDrainTask == nil,
              let sessionIdentity = self.sessionIdentity else { return }
        let token = UUID()
        self.outboxDrainToken = token
        self.outboxDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.isOutboxDrainRequested = false
                let report = await self.drainOutboxOnce()
                if report.succeeded > 0 || report.blocked > 0 {
                    // The store exposes one FIFO head per conversation. A
                    // successful or quarantined head may reveal the next one.
                    self.isOutboxDrainRequested = true
                }
            } while self.isOutboxDrainRequested
                && !Task.isCancelled
                && self.sessionIdentity == sessionIdentity
                && self.outboxDrainToken == token
            guard self.sessionIdentity == sessionIdentity,
                  self.outboxDrainToken == token else { return }
            self.outboxDrainTask = nil
            self.outboxDrainToken = nil
        }
    }

    private func drainOutboxOnce() async -> MessagingOutboxDrainReport {
        guard !self.isDrainingOutbox,
              let worker = self.outboxWorker,
              let sessionIdentity = self.sessionIdentity else { return .init() }
        self.isDrainingOutbox = true
        defer {
            if self.sessionIdentity == sessionIdentity,
               self.outboxWorker === worker {
                self.isDrainingOutbox = false
            }
        }
        do {
            let report = try await worker.drainOnce()
            guard self.sessionIdentity == sessionIdentity,
                  self.outboxWorker === worker else { return .init() }
            if report.succeeded > 0 || report.blocked > 0 || report.retryScheduled > 0 {
                self.postChange()
            }
            return report
        } catch is CancellationError {
            return .init()
        } catch {
            guard self.sessionIdentity == sessionIdentity,
                  self.outboxWorker === worker else { return .init() }
            self.postFailure(error)
            return .init()
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
            guard let components = try? self.requireComponents() else { return }
            do {
                let result = try await components.repository.perform(
                    mutation,
                    idempotencyKey: UUID().uuidString.lowercased()
                )
                try self.validateCurrentSession(components)
                if case .member(let member) = result {
                    try await components.storage.upsert(members: [member])
                    try self.validateCurrentSession(components)
                    self.postChange(conversationIDs: [member.conversationID])
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrentSession(components) else { return }
                let classifier = ParseMessagingErrorClassifier()
                if classifier.isMessagingAccessRevokedError(error) {
                    try? await components.storage.removeConversation(
                        id: mutation.conversationID
                    )
                    guard self.isCurrentSession(components) else { return }
                    self.postChange(conversationIDs: [mutation.conversationID])
                    self.postFailure(error)
                } else if !classifier.isRetryableMessagingError(error) {
                    self.postFailure(error)
                }
            }
        }
    }

    // MARK: - Helpers

    private struct Components {
        let sessionIdentity: UUID
        let userID: MessagingUserID
        let store: GRDBMessagingStore
        let storage: ParseMessagingStorage
        let repository: ParseMessagingRepository
    }

    private func requireComponents() throws -> Components {
        guard let sessionIdentity = self.sessionIdentity,
              let userID = self.authenticatedUserID,
              let store = self.store,
              let storage = self.storage,
              let repository = self.repository else {
            throw ParseMessagingManagerError.notInitialized
        }
        return Components(
            sessionIdentity: sessionIdentity,
            userID: userID,
            store: store,
            storage: storage,
            repository: repository
        )
    }

    private func isCurrentSession(_ components: Components) -> Bool {
        self.lifecycleIdentity == components.sessionIdentity
            && self.sessionIdentity == components.sessionIdentity
            && self.authenticatedUserID == components.userID
            && self.store === components.store
            && self.storage === components.storage
            && self.repository === components.repository
    }

    private func validateCurrentSession(_ components: Components) throws {
        guard self.isCurrentSession(components) else {
            throw CancellationError()
        }
    }

    private func validateLifecycle(identity: UUID) throws {
        guard self.lifecycleIdentity == identity else {
            throw CancellationError()
        }
    }

    private func requireRetryableCacheFallback(
        after error: Error,
        components: Components,
        purgeOnAccessRevoked: () async throws -> Void
    ) async throws {
        try self.validateCurrentSession(components)
        let classifier = ParseMessagingErrorClassifier()
        guard classifier.isRetryableMessagingError(error) else {
            if classifier.isMessagingAccessRevokedError(error) {
                try await purgeOnAccessRevoked()
                try self.validateCurrentSession(components)
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

    private static func makeStore(databaseURL: URL) async throws -> GRDBMessagingStore {
        try await Task.detached(priority: .userInitiated) {
            try GRDBMessagingStore(databaseURL: databaseURL)
        }.value
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

    private func postChange(
        conversationIDs: Set<MessagingConversationID>? = nil
    ) {
        let userInfo = conversationIDs.map {
            [ParseMessagingNotificationKey.conversationIDs: $0]
        }
        NotificationCenter.default.post(
            name: .parseMessagingDidChange,
            object: self,
            userInfo: userInfo
        )
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
