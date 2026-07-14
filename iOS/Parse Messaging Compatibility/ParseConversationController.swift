//
//  ParseConversationController.swift
//  Jibber
//

import Combine
import Foundation
import MessagingContracts
import MessagingPersistence
import ParseCore

private enum ParseUnreadMessageResolutionError: LocalizedError {
    case paginationDidNotAdvance(String)
    case replyPaginationDidNotAdvance(String)

    var errorDescription: String? {
        switch self {
        case .paginationDidNotAdvance(let conversationID):
            return "Could not load older unread messages for conversation \(conversationID)."
        case .replyPaginationDidNotAdvance(let messageID):
            return "Could not load older unread replies for message \(messageID)."
        }
    }
}

struct ParseUnreadMessageTarget {
    let unreadMessage: ParseMessage
    let visibleRootMessage: ParseMessage

    var isReply: Bool { self.unreadMessage.id != self.visibleRootMessage.id }
}

@MainActor
final class ParseConversationController: Hashable {

    let conversationID: ParseConversationID
    private(set) var hasLoadedAllPreviousMessages = false

    @Published private(set) var conversation: ParseConversation?
    @Published private(set) var parseMessages: [ParseMessage] = []
    @Published private(set) var members: [ParseConversationMember] = []
    @Published private(set) var typingMembers: [ParseConversationMember] = []

    private let manager: ParseMessagingManager
    private let conversationChangeSubject = PassthroughSubject<ParseEntityChange<ParseConversation>, Never>()
    private let messageChangesSubject = PassthroughSubject<[ParseListChange<ParseMessage>], Never>()
    private let memberChangesSubject = PassthroughSubject<[ParseListChange<ParseConversationMember>], Never>()
    private var allSnapshots: [MessagingMessageSnapshot] = []
    private var nextMessageCursor: MessagingCursor?
    private var hasAuthoritativeRemoteMessagePage = false
    private var messagingChangeCancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var cachedStateRefreshTask: Task<Void, Never>?
    private var isCachedStateRefreshPending = false
    private var cachedStateRevision: UInt = 0
    private var synchronizationTask: Task<Void, Error>?
    private var typingExpiryTask: Task<Void, Never>?

    init(
        conversationID: ParseConversationID,
        manager: ParseMessagingManager,
        automaticallySynchronize: Bool = true,
        observesMessagingChanges: Bool = true
    ) {
        self.conversationID = conversationID
        self.manager = manager
        if observesMessagingChanges {
            self.observeMessagingChanges()
        }
        if automaticallySynchronize {
            self.refreshTask = Task { @MainActor [weak self] in
                do {
                    try await self?.synchronize()
                } catch {
                    logError(error)
                }
            }
        }
    }

    convenience init(
        conversationID: ParseConversationID,
        automaticallySynchronize: Bool = true
    ) {
        self.init(
            conversationID: conversationID,
            manager: .shared,
            automaticallySynchronize: automaticallySynchronize
        )
    }

    static func controller(for conversationID: String) -> ParseConversationController {
        JibberMessagingClient.shared.conversationController(for: conversationID)
            ?? ParseConversationController(conversationID: conversationID)
    }

    static func controller(for conversation: ParseConversation) -> ParseConversationController {
        self.controller(for: conversation.id)
    }

    convenience init(
        conversationID: String,
        manager: ParseMessagingManager,
        automaticallySynchronize: Bool = true
    ) {
        self.init(
            conversationID: ParseConversationID(conversationID),
            manager: manager,
            automaticallySynchronize: automaticallySynchronize
        )
    }

    convenience init(
        conversationID: String,
        automaticallySynchronize: Bool = true
    ) {
        self.init(
            conversationID: ParseConversationID(conversationID),
            manager: .shared,
            automaticallySynchronize: automaticallySynchronize
        )
    }

    deinit {
        self.refreshTask?.cancel()
        self.cachedStateRefreshTask?.cancel()
        self.synchronizationTask?.cancel()
        self.typingExpiryTask?.cancel()
    }

    var conversationId: String? { self.conversationID.rawValue }
    var cid: ParseConversationID? { self.conversationID }
    var channel: ParseConversation? { self.conversation }
    var memberCount: Int { self.members.filter(\.isActive).count }
    var messages: [ParseMessage] { self.parseMessages }
    var rootMessage: ParseMessage? { nil }
    var messageSequence: MessageSequence? { self.conversation }
    var messageArray: [Messageable] { self.parseMessages }

    var conversationChangePublisher: AnyPublisher<ParseEntityChange<ParseConversation>, Never> {
        self.conversationChangeSubject.eraseToAnyPublisher()
    }

    var channelChangePublisher: AnyPublisher<ParseEntityChange<ParseConversation>, Never> {
        self.conversationChangePublisher
    }

    var messageSequenceChangePublisher: AnyPublisher<ParseEntityChange<MessageSequence>, Never> {
        self.conversationChangeSubject
            .map { change in change.map { $0 as MessageSequence } }
            .eraseToAnyPublisher()
    }

    var messagesChangesPublisher: AnyPublisher<[ParseListChange<ParseMessage>], Never> {
        self.messageChangesSubject.eraseToAnyPublisher()
    }

    var membersChangesPublisher: AnyPublisher<[ParseListChange<ParseConversationMember>], Never> {
        self.memberChangesSubject.eraseToAnyPublisher()
    }

    var memberEventPublisher: AnyPublisher<[ParseListChange<ParseConversationMember>], Never> {
        self.membersChangesPublisher
    }

    var areTypingEventsEnabled: Bool { true }

    var typingMembersPublisher: AnyPublisher<[ParseConversationMember], Never> {
        self.$typingMembers.eraseToAnyPublisher()
    }

    var typingPeoplePublisher: AnyPublisher<[PersonType], Never> {
        self.$typingMembers
            .map { $0.compactMap(\.person) }
            .eraseToAnyPublisher()
    }

    var typingUsersPublisher: AnyPublisher<[PersonType], Never> {
        self.typingPeoplePublisher
    }

    func sendKeystrokeEvent(completion: ((Error?) -> Void)? = nil) {
        do {
            try self.setTyping(true)
            completion?(nil)
        } catch {
            completion?(error)
        }
    }

    func sendStopTypingEvent(completion: ((Error?) -> Void)? = nil) {
        do {
            try self.setTyping(false)
            completion?(nil)
        } catch {
            completion?(error)
        }
    }

    func getMessage(withId id: String) -> Messageable? {
        self.parseMessages.first { $0.id == id || $0.serverID == id }
    }

    func messageController(
        for messageID: String,
        automaticallySynchronize: Bool = true
    ) -> ParseMessageController {
        ParseMessageController(
            conversationID: self.conversationID,
            messageID: messageID,
            manager: self.manager,
            automaticallySynchronize: automaticallySynchronize
        )
    }

    // MARK: - Reads

    func synchronize(pageSize: Int = 50) async throws {
        if let synchronizationTask {
            try await synchronizationTask.value
            return
        }

        let synchronizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.performSynchronization(pageSize: pageSize)
        }
        self.synchronizationTask = synchronizationTask
        defer { self.synchronizationTask = nil }
        try await synchronizationTask.value
    }

    private func performSynchronization(pageSize: Int) async throws {
        try await self.applyCachedState(pageSize: pageSize)
        guard self.manager.isInitialized,
              let repository = self.manager.repository,
              let store = self.manager.store else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }

        let conversation = try await repository.conversation(id: self.conversationID.rawValue)
        try await self.manager.upsertConversation(
            conversation,
            expectedStore: store
        )
        _ = try await self.manager.members(conversationID: self.conversationID.rawValue)
        let messagePage = try await self.manager.messages(
            conversationID: self.conversationID.rawValue,
            pageSize: pageSize
        )
        _ = try await self.manager.pinnedMessages(
            conversationID: self.conversationID.rawValue
        )
        try await self.applyCachedState(pageSize: max(pageSize, self.allSnapshots.count + 1))
        if !self.hasAuthoritativeRemoteMessagePage
            || (self.hasLoadedAllPreviousMessages && messagePage.hasMore) {
            self.nextMessageCursor = messagePage.nextCursor
            self.hasLoadedAllPreviousMessages = !messagePage.hasMore
            self.hasAuthoritativeRemoteMessagePage = true
        }
    }

    func loadPreviousMessages(before messageID: String? = nil, limit: Int = 25) async throws {
        let cursor: MessagingCursor?
        if let messageID = messageID,
           let snapshot = self.allSnapshots.first(where: {
               $0.stableID == messageID || $0.objectID == messageID
           }) {
            cursor = MessagingCursor.messages(
                conversationID: self.conversationID.rawValue,
                sortDate: snapshot.sortDate,
                stableID: snapshot.objectID ?? snapshot.stableID
            )
        } else {
            cursor = self.nextMessageCursor
        }

        guard cursor != nil || self.allSnapshots.isEmpty else {
            self.hasLoadedAllPreviousMessages = true
            return
        }
        let page = try await self.manager.messages(
            conversationID: self.conversationID.rawValue,
            before: cursor,
            pageSize: limit
        )
        self.allSnapshots = ParseMessagingControllerSupport.merge(
            self.allSnapshots,
            with: page.items
        )
        self.nextMessageCursor = page.nextCursor
        self.hasLoadedAllPreviousMessages = !page.hasMore
        self.hasAuthoritativeRemoteMessagePage = true
        try await self.publishCurrentState()
    }

    func loadPreviousMessages(including messageID: String, limit: Int = 25) async throws {
        if !self.allSnapshots.contains(where: { $0.stableID == messageID || $0.objectID == messageID }) {
            repeat {
                try await self.loadPreviousMessages(limit: limit)
            } while !self.hasLoadedAllPreviousMessages
                && !self.allSnapshots.contains(where: {
                    $0.stableID == messageID || $0.objectID == messageID
                })
        }
    }

    /// Parse keyset pagination is descending. A refresh of the newest page is
    /// the equivalent operation for callers that previously requested newer
    /// Stream messages.
    func loadNextMessages(after messageID: String? = nil, limit: Int = 25) async throws {
        let page = try await self.manager.messages(
            conversationID: self.conversationID.rawValue,
            pageSize: limit
        )
        self.allSnapshots = ParseMessagingControllerSupport.merge(
            self.allSnapshots,
            with: page.items
        )
        try await self.publishCurrentState()
    }

    func loadNextMessages(including messageID: String, limit: Int = 25) async throws {
        try await self.loadNextMessages(after: messageID, limit: limit)
    }

    func getOldestUnreadMessage(withUserID userID: String) -> ParseMessage? {
        guard let member = self.members.first(where: { $0.userID == userID }) else { return nil }
        if let lastReadAt = member.lastReadAt {
            return self.parseMessages.reversed().first { $0.createdAt > lastReadAt }
        }
        return self.parseMessages.last
    }

    /// Loads enough root and reply history to resolve the true oldest unread
    /// timeline item. Replies resolve to their visible root because the main
    /// conversation collection displays roots rather than thread rows.
    func loadOldestUnreadMessage(pageSize: Int = 25) async throws -> ParseUnreadMessageTarget? {
        precondition(pageSize > 0)
        // Resolve against the latest reconciled member count/message page even
        // if a coalesced notification refresh has not run on the main actor yet.
        try await self.applyCachedState(
            pageSize: max(50, self.allSnapshots.count + 10)
        )
        var hydratedReplyRootIDs: Set<String> = []

        while true {
            try Task.checkCancellation()

            guard let unreadBoundary = self.currentUnreadBoundary,
                  unreadBoundary.unreadCount > 0 else {
                return nil
            }
            let serverUnreadCount = unreadBoundary.unreadCount

            hydratedReplyRootIDs = try await self.hydrateRepliesForUnreadResolution(
                alreadyHydratedRootIDs: hydratedReplyRootIDs
            )
            try Task.checkCancellation()

            // Reply hydration suspends this MainActor method. Realtime receipt
            // or membership updates may change the authoritative unread count
            // while it is suspended, so restart with the current value rather
            // than resolving against a stale boundary.
            guard self.currentUnreadBoundary == unreadBoundary else {
                hydratedReplyRootIDs.removeAll(keepingCapacity: true)
                continue
            }

            // The backend currently preserves replies when their root is
            // tombstoned, but its member unread count can still include those
            // now-unreachable reply receipts. Heal only those inaccessible
            // items when the user explicitly invokes unread navigation, and
            // remove them from this resolution boundary immediately.
            let inaccessibleUnreadReplies = self.inaccessibleUnreadReplies
            try await self.repairInaccessibleUnreadReplies(inaccessibleUnreadReplies)
            try Task.checkCancellation()
            guard self.currentUnreadBoundary == unreadBoundary else {
                hydratedReplyRootIDs.removeAll(keepingCapacity: true)
                continue
            }

            let loadedUnreadCandidates = self.loadedUnreadCandidates
            let resolution = MessagingUnreadTargetResolver.resolveCandidate(
                serverUnreadCount: serverUnreadCount,
                loadedUnreadCandidatesOldestFirst: loadedUnreadCandidates.map(\.candidate),
                hasLoadedAll: self.hasLoadedAllPreviousMessages
            )
            switch resolution {
            case .target(let target):
                guard let root = self.parseMessages.first(where: {
                    $0.id == target.visibleRootMessageID
                        || $0.serverID == target.visibleRootMessageID
                }) else { return nil }
                let unreadMessage: ParseMessage?
                if root.id == target.unreadMessageID || root.serverID == target.unreadMessageID {
                    unreadMessage = root
                } else {
                    unreadMessage = root.replies.first {
                        $0.id == target.unreadMessageID || $0.serverID == target.unreadMessageID
                    }
                }
                guard let unreadMessage else { return nil }
                return ParseUnreadMessageTarget(
                    unreadMessage: unreadMessage,
                    visibleRootMessage: root
                )
            case .none:
                return nil
            case .needsOlderPage:
                break
            }

            let previousRootCount = self.parseMessages.count
            let previousCursor = self.nextMessageCursor
            try await self.loadPreviousMessages(limit: pageSize)
            try Task.checkCancellation()

            guard self.hasLoadedAllPreviousMessages
                    || self.parseMessages.count != previousRootCount
                    || self.nextMessageCursor != previousCursor else {
                throw ParseUnreadMessageResolutionError.paginationDidNotAdvance(
                    self.conversationID.rawValue
                )
            }
        }
    }

    func getMostRecentMessage(fromCurrentUser: Bool) -> ParseMessage? {
        self.parseMessages.first { $0.isFromCurrentUser == fromCurrentUser }
    }

    private struct LoadedUnreadCandidate {
        let sortDate: Date
        let candidate: MessagingUnreadTargetCandidate
    }

    /// Only receipt-derived membership fields invalidate unread resolution.
    /// Typing, visibility, role, and other member updates share Parse's broad
    /// `updatedAt` version but cannot change the unread boundary and must not
    /// restart an in-flight reply hydration pass.
    private struct UnreadBoundary: Equatable {
        let memberID: String
        let unreadCount: Int
        let lastReadMessageID: String?
        let lastReadAt: Date?
    }

    private var currentUnreadBoundary: UnreadBoundary? {
        guard let member = self.members.first(where: \.isCurrentUser) else { return nil }
        return UnreadBoundary(
            memberID: member.objectID,
            unreadCount: member.unreadCount,
            lastReadMessageID: member.lastReadMessageID,
            lastReadAt: member.lastReadAt
        )
    }

    private var loadedUnreadCandidates: [LoadedUnreadCandidate] {
        self.parseMessages.flatMap { root -> [LoadedUnreadCandidate] in
            // Deleted roots are absent from the collection data source, and
            // their replies therefore have no visible scroll target.
            guard !root.isDeleted else { return [] }
            var candidates: [LoadedUnreadCandidate] = []
            if self.isUnread(root) {
                candidates.append(
                    LoadedUnreadCandidate(
                        sortDate: root.createdAt,
                        candidate: MessagingUnreadTargetCandidate(
                            unreadMessageID: root.id,
                            visibleRootMessageID: root.id
                        )
                    )
                )
            }
            candidates.append(contentsOf: root.replies.compactMap { reply in
                guard self.isUnread(reply) else { return nil }
                return LoadedUnreadCandidate(
                    sortDate: reply.createdAt,
                    candidate: MessagingUnreadTargetCandidate(
                        unreadMessageID: reply.id,
                        visibleRootMessageID: root.id
                    )
                )
            })
            return candidates
        }.sorted { lhs, rhs in
            if lhs.sortDate == rhs.sortDate {
                return lhs.candidate.unreadMessageID < rhs.candidate.unreadMessageID
            }
            return lhs.sortDate < rhs.sortDate
        }
    }

    private func isUnread(_ message: ParseMessage) -> Bool {
        !message.isFromCurrentUser && !message.isConsumedByMe && !message.isDeleted
    }

    private var inaccessibleUnreadReplies: [ParseMessage] {
        self.parseMessages
            .filter(\.isDeleted)
            .flatMap(\.replies)
            .filter(self.isUnread)
    }

    private func repairInaccessibleUnreadReplies(_ replies: [ParseMessage]) async throws {
        guard !replies.isEmpty,
              let expectedStore = self.manager.store,
              let userID = self.manager.authenticatedUserID else { return }

        for reply in replies {
            try Task.checkCancellation()
            guard let messageID = reply.serverID else { continue }
            let idempotencyKey = [
                "unread-repair",
                userID,
                self.conversationID.rawValue,
                messageID
            ].joined(separator: ".")
            _ = try await self.manager.enqueue(
                .markRead(
                    conversationID: self.conversationID.rawValue,
                    messageID: messageID,
                    messageCreatedAt: reply.createdAt,
                    readAt: Date()
                ),
                idempotencyKey: idempotencyKey,
                expectedStore: expectedStore,
                expectedUserID: userID
            )
        }
    }

    /// Reply pages are separate from root pages in Parse. Hydrate each newly
    /// loaded root once during this explicit navigation flow so the
    /// authoritative member count can be compared with both roots and replies.
    /// This work is intentionally not performed by every visible cell.
    private func hydrateRepliesForUnreadResolution(
        alreadyHydratedRootIDs: Set<String>
    ) async throws -> Set<String> {
        var hydratedRootIDs = alreadyHydratedRootIDs
        var didLoadReplies = false
        let rootSnapshots = self.allSnapshots.filter { $0.replyToMessageID == nil }

        for root in rootSnapshots where !hydratedRootIDs.contains(root.stableID) {
            try Task.checkCancellation()
            hydratedRootIDs.insert(root.stableID)

            guard (root.replyCount ?? 0) > 0,
                  let rootServerID = root.objectID else {
                continue
            }

            var cursor: MessagingCursor?
            repeat {
                let page = try await self.manager.replies(
                    messageID: rootServerID,
                    before: cursor,
                    pageSize: 100
                )
                try Task.checkCancellation()
                if !page.items.isEmpty {
                    self.allSnapshots = ParseMessagingControllerSupport.merge(
                        self.allSnapshots,
                        with: page.items
                    )
                    didLoadReplies = true
                }

                guard page.hasMore else { break }
                guard let nextCursor = page.nextCursor, nextCursor != cursor else {
                    throw ParseUnreadMessageResolutionError.replyPaginationDidNotAdvance(
                        rootServerID
                    )
                }
                cursor = nextCursor
            } while true
        }

        if didLoadReplies {
            try await self.publishCurrentState()
        }
        return hydratedRootIDs
    }

    // MARK: - Writes

    @discardableResult
    func createNewMessage(with sendable: MessageSendable) async throws -> String {
        guard let expectedStore = self.manager.store,
              let authorID = self.manager.authenticatedUserID else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        let draft = try await ParseMessageDraftTranslator.draft(
            from: sendable,
            conversationID: self.conversationID,
            authorID: authorID
        )
        let staged = try await self.manager.send(
            draft,
            expectedStore: expectedStore,
            expectedUserID: authorID
        )
        self.allSnapshots = ParseMessagingControllerSupport.merge(
            self.allSnapshots,
            with: [staged]
        )
        try await self.publishCurrentState()
        await ParseOutgoingMessageHooks.messageWasQueued(
            sendable: sendable,
            conversation: self.conversation,
            members: self.members,
            isReply: false
        )
        return staged.stableID
    }

    @discardableResult
    func createNewReply(with sendable: MessageSendable, messageID: String) async throws -> String {
        guard let expectedStore = self.manager.store,
              let authorID = self.manager.authenticatedUserID else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        var threadTargetSnapshots = self.allSnapshots
        if !threadTargetSnapshots.contains(where: {
            $0.stableID == messageID || $0.objectID == messageID
        }), let cachedTarget = try await self.manager.cachedMessage(
            conversationID: self.conversationID.rawValue,
            id: messageID
        ) {
            threadTargetSnapshots = ParseMessagingControllerSupport.merge(
                threadTargetSnapshots,
                with: [cachedTarget]
            )
        }
        let rootID = try ParseMessagingControllerSupport.serverThreadRootMessageID(
            for: messageID,
            in: threadTargetSnapshots
        )
        let draft = try await ParseMessageDraftTranslator.draft(
            from: sendable,
            conversationID: self.conversationID,
            authorID: authorID,
            replyToMessageID: rootID
        )
        let staged = try await self.manager.send(
            draft,
            expectedStore: expectedStore,
            expectedUserID: authorID
        )
        self.allSnapshots = ParseMessagingControllerSupport.merge(
            self.allSnapshots,
            with: [staged]
        )
        try await self.publishCurrentState()
        await ParseOutgoingMessageHooks.messageWasQueued(
            sendable: sendable,
            conversation: self.conversation,
            members: self.members,
            isReply: true
        )
        return staged.stableID
    }

    func editMessage(with sendable: MessageSendable) async throws {
        guard let previousMessage = sendable.previousMessage else {
            throw ParseMessagingCompatibilityError.messageNotFound("previous")
        }
        guard case .text(let text) = sendable.kind else {
            throw ParseMessagingCompatibilityError.unsupportedMessageKind("edited non-text")
        }
        try await self.editMessage(messageID: previousMessage.id, text: text)
    }

    func editMessage(messageID: String, text: String) async throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try await self.queue(
            .edit(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                text: text,
                editedAt: Date()
            )
        )
    }

    func deleteMessage(_ messageID: String) async throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try await self.queue(
            .delete(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                deletedAt: Date()
            )
        )
    }

    func retryFailedMessage(_ messageID: String) async throws {
        guard let snapshot = self.allSnapshots.first(where: {
            $0.stableID == messageID || $0.objectID == messageID
        }) else {
            throw ParseMessagingCompatibilityError.messageNotFound(messageID)
        }
        try await self.manager.retryBlockedOperation(
            idempotencyKey: snapshot.clientMessageID
        )
    }

    func cancelFailedMessage(_ messageID: String) async throws {
        guard let snapshot = self.allSnapshots.first(where: {
            $0.stableID == messageID || $0.objectID == messageID
        }) else {
            throw ParseMessagingCompatibilityError.messageNotFound(messageID)
        }
        try await self.manager.cancelBlockedOperation(
            idempotencyKey: snapshot.clientMessageID
        )
    }

    func pinMessage(_ messageID: String) async throws {
        try await self.setPinned(true, messageID: messageID)
    }

    func unpinMessage(_ messageID: String) async throws {
        try await self.setPinned(false, messageID: messageID)
    }

    func setReaction(_ type: String, selected: Bool, messageID: String) async throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try await self.queue(
            .setReaction(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                type: type,
                isSelected: selected
            )
        )
    }

    func markRead(_ messageID: String) async throws {
        guard let snapshot = self.allSnapshots.first(where: {
            $0.stableID == messageID || $0.objectID == messageID
        }), let serverID = snapshot.objectID else {
            throw ParseMessagingCompatibilityError.messageNotFound(messageID)
        }
        try await self.queue(
            .markRead(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                messageCreatedAt: snapshot.sortDate,
                readAt: Date()
            )
        )
    }

    func markUnread(_ messageID: String) async throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try await self.queue(
            .markUnread(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                changedAt: Date()
            )
        )
    }

    func updateTitle(_ title: String) async throws {
        try await self.queue(
            .setConversationTitle(
                conversationID: self.conversationID.rawValue,
                title: title
            )
        )
    }

    func updateChannel(
        name: String?,
        imageURL: URL?,
        team: String?,
        completion: ((Error?) -> Void)? = nil
    ) {
        Task { @MainActor [weak self] in
            do {
                if let name = name {
                    try await self?.updateTitle(name)
                }
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }

    func deleteConversation() async throws {
        try await self.queue(
            .setConversationDeleted(
                conversationID: self.conversationID.rawValue,
                isDeleted: true,
                changedAt: Date()
            )
        )
    }

    func deleteChannel() async throws {
        try await self.deleteConversation()
    }

    func setMemberActive(userID: String, active: Bool) async throws {
        try await self.queue(
            .setMemberActive(
                conversationID: self.conversationID.rawValue,
                userID: userID,
                active: active
            )
        )
    }

    func addMembers(userIDs: Set<String>) async throws {
        for userID in userIDs {
            try await self.setMemberActive(userID: userID, active: true)
        }
    }

    func addMembers(userIds: Set<String>) async throws {
        try await self.addMembers(userIDs: userIds)
    }

    func addMembers(userIds: Set<String>, completion: ((Error?) -> Void)? = nil) {
        Task { @MainActor [weak self] in
            do {
                try await self?.addMembers(userIDs: userIds)
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }

    func removeMembers(userIDs: Set<String>) async throws {
        for userID in userIDs {
            try await self.setMemberActive(userID: userID, active: false)
        }
    }

    func removeMembers(userIds: Set<String>) async throws {
        try await self.removeMembers(userIDs: userIds)
    }

    func hideConversation() async throws {
        let member = try ParseMessagingControllerSupport.currentMember(in: self.members)
        try await self.setHidden(true, memberID: member.objectID)
    }

    func hideChannel(clearHistory: Bool = false) async throws {
        // Parse keeps tombstones/history server-side; clearHistory is
        // intentionally ignored instead of destructively deleting local data.
        try await self.hideConversation()
    }

    func showConversation() async throws {
        let member = try ParseMessagingControllerSupport.currentMember(in: self.members)
        try await self.setHidden(false, memberID: member.objectID)
    }

    func showChannel() async throws {
        try await self.showConversation()
    }

    func markRead() async throws {
        guard let newestUnread = self.parseMessages.first(where: {
            !$0.isFromCurrentUser && !$0.isConsumedByMe && !$0.isDeleted
        }) else { return }
        try await self.markRead(newestUnread.id)
    }

    func setTyping(_ isTyping: Bool) throws {
        let member = try ParseMessagingControllerSupport.currentMember(in: self.members)
        try self.manager.setTypingBestEffort(
            conversationID: self.conversationID.rawValue,
            memberID: member.objectID,
            expiresAt: isTyping ? Date().addingTimeInterval(12) : nil
        )
    }

    func add(expression: Expression) async throws {
        guard let expectedStore = self.manager.store,
              let authorID = self.manager.authenticatedUserID else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        let saved = try await expression.saveToServer()
        guard let expressionID = saved.objectId else {
            throw ParseMessagingCompatibilityError.missingExpressionID
        }
        try await self.manager.enqueue(
            .addConversationExpression(
                conversationID: self.conversationID.rawValue,
                reference: MessagingExpressionReference(
                    authorID: authorID,
                    expressionID: expressionID
                )
            ),
            expectedStore: expectedStore,
            expectedUserID: authorID
        )
        await ToastScheduler.shared.schedule(
            toastType: .success(ImageSymbol.faceSmiling, "Expression added")
        )
    }

    // MARK: - State publication

    private func observeMessagingChanges() {
        self.messagingChangeCancellable = NotificationCenter.default
            .publisher(for: .parseMessagingDidChange, object: self.manager)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    guard let self,
                          notification.affectsMessagingConversation(
                            self.conversationID.rawValue
                          ) else { return }
                    self.scheduleCachedStateRefresh()
                }
            }
    }

    private func scheduleCachedStateRefresh() {
        self.isCachedStateRefreshPending = true
        guard self.cachedStateRefreshTask == nil else { return }

        self.cachedStateRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isCachedStateRefreshPending, !Task.isCancelled {
                self.isCachedStateRefreshPending = false
                do {
                    try await self.applyCachedState(
                        pageSize: max(50, self.allSnapshots.count + 10)
                    )
                } catch is CancellationError {
                    break
                } catch {
                    logError(error)
                }
            }
            self.cachedStateRefreshTask = nil
            if self.isCachedStateRefreshPending {
                self.scheduleCachedStateRefresh()
            }
        }
    }

    private func applyCachedState(pageSize: Int) async throws {
        guard let store = self.manager.store else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        let state = try await store.cachedConversationState(
            conversationID: self.conversationID.rawValue,
            pageSize: pageSize
        )
        try Task.checkCancellation()
        guard self.manager.store === store else { throw CancellationError() }

        let previousRootCount = self.allSnapshots.lazy
            .filter { $0.replyToMessageID == nil }
            .count
        let mergedSnapshots = state.conversation == nil
            ? []
            : ParseMessagingControllerSupport.merge(
                self.allSnapshots,
                with: state.messages.items
            )
        let messagesChanged = mergedSnapshots != self.allSnapshots
        self.allSnapshots = mergedSnapshots
        self.cachedStateRevision &+= 1
        if state.messages.items.count >= previousRootCount,
           (!self.hasAuthoritativeRemoteMessagePage || state.messages.hasMore) {
            self.nextMessageCursor = state.messages.nextCursor
            self.hasLoadedAllPreviousMessages = !state.messages.hasMore
        }
        self.publishCurrentState(
            relatedState: MessagingConversationRelatedCacheState(
                members: state.members,
                conversation: state.conversation,
                pinnedMessages: state.pinnedMessages
            ),
            messagesChanged: messagesChanged
        )
    }

    private func publishCurrentState() async throws {
        guard let store = self.manager.store else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        while true {
            let revisionBeforeRead = self.cachedStateRevision
            let relatedState = try await store.cachedConversationRelatedState(
                conversationID: self.conversationID.rawValue
            )
            try Task.checkCancellation()
            guard self.manager.store === store else { throw CancellationError() }

            // A notification refresh can publish newer related state while
            // this read is suspended. Retry rather than letting the older
            // snapshot resume last and regress members/unread/conversation.
            guard self.cachedStateRevision == revisionBeforeRead else { continue }
            self.publishCurrentState(relatedState: relatedState)
            return
        }
    }

    private func publishCurrentState(
        relatedState: MessagingConversationRelatedCacheState,
        messagesChanged: Bool = true
    ) {
        let newMessages: [ParseMessage]
        if messagesChanged {
            let oldMessages = self.parseMessages
            newMessages = ParseMessagingControllerSupport.rootMessages(from: self.allSnapshots)
            let messageChanges = ParseListDiffer.changes(
                from: oldMessages,
                to: newMessages,
                identifiedBy: { $0.id },
                valuesEqual: ==
            )
            self.parseMessages = newMessages
            if !messageChanges.isEmpty {
                self.messageChangesSubject.send(messageChanges)
            }
        } else {
            newMessages = self.parseMessages
        }

        let oldMembers = self.members
        let membersChanged = oldMembers.map(\.snapshot) != relatedState.members
        let newMembers: [ParseConversationMember]
        if membersChanged {
            newMembers = relatedState.members.map(ParseConversationMember.init)
            let memberChanges = ParseListDiffer.changes(
                from: oldMembers,
                to: newMembers,
                identifiedBy: { $0.id },
                valuesEqual: ==
            )
            self.members = newMembers
            if !memberChanges.isEmpty {
                self.memberChangesSubject.send(memberChanges)
            }
            self.refreshTypingMembers()
        } else {
            newMembers = oldMembers
        }

        let oldConversation = self.conversation
        let newConversation = relatedState.conversation.map {
            let pinnedMessages = relatedState.pinnedMessages.isEmpty
                ? newMessages.filter(\.isPinned)
                : relatedState.pinnedMessages.map { ParseMessage(snapshot: $0) }
            return ParseConversation(
                snapshot: $0,
                members: newMembers,
                messages: newMessages,
                pinnedMessages: pinnedMessages
            )
        }
        guard oldConversation != newConversation else { return }
        self.conversation = newConversation
        switch (oldConversation, newConversation) {
        case (nil, let new?):
            self.conversationChangeSubject.send(.create(new))
        case (let old?, nil):
            self.conversationChangeSubject.send(.remove(old))
        case (let old?, let new?) where old != new:
            self.conversationChangeSubject.send(.update(new))
        default:
            break
        }
    }

    private func refreshTypingMembers() {
        self.typingExpiryTask?.cancel()
        let now = Date()
        self.typingMembers = self.members.filter {
            !$0.isCurrentUser && $0.isTyping(at: now)
        }
        guard let nextExpiry = self.typingMembers.compactMap(\.typingExpiresAt).min() else { return }
        self.typingExpiryTask = Task { @MainActor [weak self] in
            let interval = max(0, nextExpiry.timeIntervalSinceNow)
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }
            self?.refreshTypingMembers()
        }
    }

    private func setPinned(_ isPinned: Bool, messageID: String) async throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try await self.queue(
            .setPinned(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                isPinned: isPinned,
                changedAt: Date()
            )
        )
    }

    private func setHidden(_ isHidden: Bool, memberID: String) async throws {
        try await self.queue(
            .setMemberHidden(
                conversationID: self.conversationID.rawValue,
                memberID: memberID,
                isHidden: isHidden
            )
        )
    }

    private func queue(_ mutation: MessagingMutation) async throws {
        try await self.manager.enqueue(mutation)
    }

    nonisolated static func == (
        lhs: ParseConversationController,
        rhs: ParseConversationController
    ) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
