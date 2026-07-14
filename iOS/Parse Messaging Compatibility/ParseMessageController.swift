//
//  ParseMessageController.swift
//  Jibber
//

import Combine
import Foundation
import MessagingContracts
import MessagingPersistence
import ParseCore

enum ParseMessageListOrdering {
    case bottomToTop
}

enum ParseMessageControllerObservationMode {
    case live
    case replyPreview
}

@MainActor
final class ParseMessageController: Hashable {

    let conversationID: ParseConversationID
    let messageID: String
    var listOrdering: ParseMessageListOrdering = .bottomToTop

    @Published private(set) var message: ParseMessage?
    @Published private(set) var replies: [ParseMessage] = []

    private(set) var hasLoadedAllPreviousReplies = false
    var hasLoadedAllPreviousMessages: Bool { self.hasLoadedAllPreviousReplies }

    private let manager: ParseMessagingManager
    private let conversationController: ParseConversationController
    private let messageChangeSubject = PassthroughSubject<ParseEntityChange<ParseMessage>, Never>()
    private let replyChangesSubject = PassthroughSubject<[ParseListChange<ParseMessage>], Never>()
    private var replySnapshots: [MessagingMessageSnapshot] = []
    private var nextReplyCursor: MessagingCursor?
    private var hasAuthoritativeRemoteReplyPage = false
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?
    private var cachedRepliesRefreshTask: Task<Void, Never>?
    private var isCachedRepliesRefreshPending = false

    init(
        conversationID: ParseConversationID,
        messageID: String,
        manager: ParseMessagingManager,
        automaticallySynchronize: Bool = true,
        observationMode: ParseMessageControllerObservationMode = .live
    ) {
        self.conversationID = conversationID
        self.messageID = messageID
        self.manager = manager
        self.conversationController = ParseConversationController(
            conversationID: conversationID,
            manager: manager,
            automaticallySynchronize: false,
            observesMessagingChanges: observationMode == .live
        )
        if observationMode == .live {
            self.observeState()
        }
        if automaticallySynchronize, observationMode == .live {
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
        messageID: String,
        automaticallySynchronize: Bool = true
    ) {
        self.init(
            conversationID: conversationID,
            messageID: messageID,
            manager: .shared,
            automaticallySynchronize: automaticallySynchronize
        )
    }

    static func controller(
        for message: Messageable,
        automaticallySynchronize: Bool = true
    ) -> ParseMessageController? {
        guard !message.conversationId.isEmpty, !message.id.isEmpty else { return nil }
        let controller = ParseMessageController(
            conversationID: message.conversationId,
            messageID: message.id,
            automaticallySynchronize: automaticallySynchronize
        )
        if let parseMessage = message as? ParseMessage {
            controller.updateReplyPreviewRoot(with: parseMessage)
        }
        return controller
    }

    /// A visible-cell controller that performs explicit cache/server reads but
    /// installs no conversation or global messaging observers. Cells are
    /// reused frequently, so live observer fanout belongs to the owning
    /// conversation controller rather than to every preview.
    static func replyPreviewController(for message: ParseMessage) -> ParseMessageController? {
        guard !message.conversationId.isEmpty, !message.id.isEmpty else { return nil }
        let controller = ParseMessageController(
            conversationID: ParseConversationID(message.conversationId),
            messageID: message.id,
            manager: .shared,
            automaticallySynchronize: false,
            observationMode: .replyPreview
        )
        controller.updateReplyPreviewRoot(with: message)
        return controller
    }

    static func controller(
        for conversationID: String,
        messageID: String
    ) -> ParseMessageController? {
        guard !conversationID.isEmpty, !messageID.isEmpty else { return nil }
        return ParseMessageController(
            conversationID: conversationID,
            messageID: messageID
        )
    }

    static func controller(
        for conversationId: String,
        messageId: String
    ) -> ParseMessageController? {
        self.controller(for: conversationId, messageID: messageId)
    }

    convenience init(
        conversationID: String,
        messageID: String,
        manager: ParseMessagingManager,
        automaticallySynchronize: Bool = true
    ) {
        self.init(
            conversationID: ParseConversationID(conversationID),
            messageID: messageID,
            manager: manager,
            automaticallySynchronize: automaticallySynchronize
        )
    }

    convenience init(
        conversationID: String,
        messageID: String,
        automaticallySynchronize: Bool = true
    ) {
        self.init(
            conversationID: ParseConversationID(conversationID),
            messageID: messageID,
            manager: .shared,
            automaticallySynchronize: automaticallySynchronize
        )
    }

    deinit {
        self.refreshTask?.cancel()
        self.cachedRepliesRefreshTask?.cancel()
    }

    var conversationId: String? { self.conversationID.rawValue }
    var cid: ParseConversationID? { self.conversationID }
    var messageId: String { self.messageID }
    var conversation: ParseConversation? { self.conversationController.conversation }
    var members: [ParseConversationMember] { self.conversationController.members }
    var memberCount: Int { self.conversationController.memberCount }
    var rootMessage: ParseMessage? { self.message }
    var messageSequence: MessageSequence? { self.message }
    var messageArray: [Messageable] { self.replies }
    var messages: [ParseMessage] { self.replies }
    var rootMessageID: String? { self.message?.id }

    var threadParticipants: [PersonType] {
        self.message?.threadParticipants ?? []
    }

    var messageChangePublisher: AnyPublisher<ParseEntityChange<ParseMessage>, Never> {
        self.messageChangeSubject.eraseToAnyPublisher()
    }

    var reactionsPublisher: AnyPublisher<ParseEntityChange<ParseMessage>, Never> {
        self.messageChangePublisher
    }

    var messageSequenceChangePublisher: AnyPublisher<ParseEntityChange<MessageSequence>, Never> {
        self.messageChangeSubject
            .map { change in change.map { $0 as MessageSequence } }
            .eraseToAnyPublisher()
    }

    var messagesChangesPublisher: AnyPublisher<[ParseListChange<ParseMessage>], Never> {
        self.replyChangesSubject.eraseToAnyPublisher()
    }

    var repliesChangesPublisher: AnyPublisher<[ParseListChange<ParseMessage>], Never> {
        self.messagesChangesPublisher
    }

    var areTypingEventsEnabled: Bool { true }

    var typingMembersPublisher: AnyPublisher<[ParseConversationMember], Never> {
        self.conversationController.typingMembersPublisher
    }

    var typingPeoplePublisher: AnyPublisher<[PersonType], Never> {
        self.conversationController.typingPeoplePublisher
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
        self.replies.first { $0.id == id || $0.serverID == id }
    }

    // MARK: - Reads

    func synchronize(pageSize: Int = 50) async throws {
        try await self.conversationController.synchronize(pageSize: pageSize)
        try await self.loadRootIfNeeded(pageSize: pageSize)
        try await self.applyCachedRepliesAsync(pageSize: pageSize)

        guard let rootID = self.rootServerID else {
            // Optimistic roots cannot have server replies yet.
            return
        }
        let replyPage = try await self.manager.replies(
            messageID: rootID,
            pageSize: pageSize
        )
        try await self.applyCachedRepliesAsync(
            pageSize: max(pageSize, self.replySnapshots.count + 1)
        )
        if !self.hasAuthoritativeRemoteReplyPage
            || (self.hasLoadedAllPreviousReplies && replyPage.hasMore) {
            self.nextReplyCursor = replyPage.nextCursor
            self.hasLoadedAllPreviousReplies = !replyPage.hasMore
            self.hasAuthoritativeRemoteReplyPage = true
        }
    }

    /// Hydrates only the small reply preview needed by a visible root cell.
    /// This deliberately avoids synchronizing the entire conversation for each
    /// reused cell while preserving the existing reply summary and unread badge.
    func synchronizeReplyPreview(pageSize: Int = 3) async throws {
        precondition(pageSize > 0)
        guard let message, message.totalReplyCount > 0 else { return }

        try await self.applyCachedRepliesAsync(
            pageSize: pageSize,
            preservingExisting: true
        )
        try Task.checkCancellation()
        guard let rootID = self.rootServerID else { return }

        // Always refresh the preview from Parse. A non-empty cache can be
        // incomplete or stale and must not suppress a newer reply or unread
        // receipt state indefinitely.
        let replyPage = try await self.manager.replies(
            messageID: rootID,
            pageSize: pageSize
        )
        try Task.checkCancellation()
        try await self.applyCachedRepliesAsync(pageSize: pageSize)
        if !self.hasAuthoritativeRemoteReplyPage
            || (self.hasLoadedAllPreviousReplies && replyPage.hasMore) {
            self.nextReplyCursor = replyPage.nextCursor
            self.hasLoadedAllPreviousReplies = !replyPage.hasMore
            self.hasAuthoritativeRemoteReplyPage = true
        }
    }

    /// Re-applies the small visible-cell preview after LiveQuery has already
    /// reconciled a reply or receipt into GRDB. This is cache-only so a receipt
    /// event cannot fan out redundant Parse requests across visible cells.
    func refreshCachedReplyPreview(pageSize: Int = 3) async throws {
        precondition(pageSize > 0)
        guard self.message?.totalReplyCount ?? 0 > 0 else { return }
        try await self.applyCachedRepliesAsync(pageSize: pageSize)
    }

    /// Refreshes the root snapshot without discarding replies already hydrated
    /// by this preview controller. Diffable data-source reconfiguration can
    /// otherwise replace a rich root with a root-only value of the same ID.
    func updateReplyPreviewRoot(with root: ParseMessage) {
        guard root.id == self.messageID || root.serverID == self.messageID else { return }
        self.replySnapshots = ParseMessagingControllerSupport.merge(
            self.replySnapshots,
            with: root.replies.map(\.snapshot)
        )
        self.publishReplies()
        self.updateRoot(with: root.snapshot)
    }

    func loadPreviousReplies(before messageID: String? = nil, limit: Int = 25) async throws {
        guard let rootID = self.rootServerID else {
            throw ParseMessagingCompatibilityError.messageHasNotReachedServer(self.messageID)
        }
        let cursor: MessagingCursor?
        if let messageID = messageID,
           let snapshot = self.replySnapshots.first(where: {
               $0.stableID == messageID || $0.objectID == messageID
           }) {
            cursor = MessagingCursor.replies(
                messageID: rootID,
                sortDate: snapshot.sortDate,
                stableID: snapshot.objectID ?? snapshot.stableID
            )
        } else {
            cursor = self.nextReplyCursor
        }

        guard cursor != nil || self.replySnapshots.isEmpty else {
            self.hasLoadedAllPreviousReplies = true
            return
        }
        let page = try await self.manager.replies(
            messageID: rootID,
            before: cursor,
            pageSize: limit
        )
        self.replySnapshots = ParseMessagingControllerSupport.merge(
            self.replySnapshots,
            with: page.items
        )
        self.nextReplyCursor = page.nextCursor
        self.hasLoadedAllPreviousReplies = !page.hasMore
        self.hasAuthoritativeRemoteReplyPage = true
        self.publishReplies()
    }

    func loadPreviousReplies(including messageID: String, limit: Int = 25) async throws {
        repeat {
            if self.replySnapshots.contains(where: {
                $0.stableID == messageID || $0.objectID == messageID
            }) {
                return
            }
            try await self.loadPreviousReplies(limit: limit)
        } while !self.hasLoadedAllPreviousReplies
    }

    func loadNextReplies(after messageID: String? = nil, limit: Int = 25) async throws {
        guard let rootID = self.rootServerID else {
            throw ParseMessagingCompatibilityError.messageHasNotReachedServer(self.messageID)
        }
        let page = try await self.manager.replies(messageID: rootID, pageSize: limit)
        self.replySnapshots = ParseMessagingControllerSupport.merge(
            self.replySnapshots,
            with: page.items
        )
        self.publishReplies()
    }

    func loadNextReplies(including messageID: String, limit: Int = 25) async throws {
        try await self.loadNextReplies(after: messageID, limit: limit)
    }

    /// Reactions and receipts are included with every Parse message snapshot.
    func loadReactions() async throws {
        if let rootID = self.rootServerID,
           let cached = try await self.manager.cachedMessage(
            conversationID: self.conversationID.rawValue,
            id: rootID
           ) {
            self.updateRoot(with: cached)
        }
    }

    func getMostRecent(fromCurrentUser: Bool) -> ParseMessage? {
        var allMessages = self.replies
        if let message = self.message {
            allMessages.append(message)
        }
        return allMessages.sorted { $0.createdAt > $1.createdAt }
            .first { $0.isFromCurrentUser == fromCurrentUser }
    }

    // MARK: - Writes

    @discardableResult
    func createNewReply(with sendable: MessageSendable) async throws -> String {
        let id = try await self.conversationController.createNewReply(
            with: sendable,
            messageID: self.messageID
        )
        try await self.applyCachedRepliesAsync(
            pageSize: max(50, self.replySnapshots.count + 10)
        )
        return id
    }

    func editMessage(with sendable: MessageSendable) async throws {
        guard case .text(let text) = sendable.kind else {
            throw ParseMessagingCompatibilityError.unsupportedMessageKind("edited non-text")
        }
        try await self.conversationController.editMessage(
            messageID: self.messageID,
            text: text
        )
    }

    func editMessage(text: String) async throws {
        try await self.conversationController.editMessage(
            messageID: self.messageID,
            text: text
        )
    }

    func deleteMessage() async throws {
        try await self.conversationController.deleteMessage(self.messageID)
    }

    func retryFailedMessage() async throws {
        try await self.conversationController.retryFailedMessage(self.messageID)
    }

    func cancelFailedMessage() async throws {
        try await self.conversationController.cancelFailedMessage(self.messageID)
    }

    func pinMessage() async throws {
        try await self.conversationController.pinMessage(self.messageID)
    }

    func unpinMessage() async throws {
        try await self.conversationController.unpinMessage(self.messageID)
    }

    func setReaction(_ type: String, selected: Bool) async throws {
        try await self.conversationController.setReaction(
            type,
            selected: selected,
            messageID: self.messageID
        )
    }

    func markRead() async throws {
        try await self.conversationController.markRead(self.messageID)
    }

    func markUnread() async throws {
        try await self.conversationController.markUnread(self.messageID)
    }

    func setTyping(_ isTyping: Bool) throws {
        try self.conversationController.setTyping(isTyping)
    }

    func add(expression: Expression) async throws {
        guard let rootID = self.rootServerID else {
            throw ParseMessagingCompatibilityError.messageHasNotReachedServer(self.messageID)
        }
        guard let expectedStore = self.manager.store,
              let authorID = self.manager.authenticatedUserID else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        let saved = try await expression.saveToServer()
        guard let expressionID = saved.objectId else {
            throw ParseMessagingCompatibilityError.missingExpressionID
        }
        try await self.manager.enqueue(
            .addMessageExpression(
                conversationID: self.conversationID.rawValue,
                messageID: rootID,
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

    func updateTitle(_ title: String) async throws {
        try await self.conversationController.updateTitle(title)
    }

    func setMemberActive(userID: String, active: Bool) async throws {
        try await self.conversationController.setMemberActive(
            userID: userID,
            active: active
        )
    }

    func hideConversation() async throws {
        try await self.conversationController.hideConversation()
    }

    func showConversation() async throws {
        try await self.conversationController.showConversation()
    }

    // MARK: - State

    private var rootServerID: String? {
        self.message?.serverID
    }

    private func observeState() {
        self.conversationController.$parseMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                guard let self else { return }
                if let root = messages.first(where: {
                    $0.id == self.messageID || $0.serverID == self.messageID
                }) {
                    self.updateRoot(with: root.snapshot)
                } else if let oldMessage = self.message {
                    self.message = nil
                    self.replies = []
                    self.replySnapshots = []
                    self.messageChangeSubject.send(.remove(oldMessage))
                }
            }
            .store(in: &self.cancellables)

        NotificationCenter.default
            .publisher(for: .parseMessagingDidChange, object: self.manager)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    guard let self,
                          notification.affectsMessagingConversation(
                            self.conversationID.rawValue
                          ),
                          self.rootServerID != nil else { return }
                    self.scheduleCachedRepliesRefresh()
                }
            }
            .store(in: &self.cancellables)
    }

    private func scheduleCachedRepliesRefresh() {
        self.isCachedRepliesRefreshPending = true
        guard self.cachedRepliesRefreshTask == nil else { return }

        self.cachedRepliesRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isCachedRepliesRefreshPending, !Task.isCancelled {
                self.isCachedRepliesRefreshPending = false
                guard self.rootServerID != nil else { break }
                do {
                    try await self.applyCachedRepliesAsync(
                        pageSize: max(50, self.replySnapshots.count + 10)
                    )
                } catch is CancellationError {
                    break
                } catch {
                    logError(error)
                }
            }
            self.cachedRepliesRefreshTask = nil
            if self.isCachedRepliesRefreshPending {
                self.scheduleCachedRepliesRefresh()
            }
        }
    }

    private func loadRootIfNeeded(pageSize: Int) async throws {
        if self.message != nil { return }
        repeat {
            try await self.conversationController.loadPreviousMessages(limit: pageSize)
            if self.message != nil { return }
        } while !self.conversationController.hasLoadedAllPreviousMessages

        if self.message == nil {
            throw ParseMessagingCompatibilityError.messageNotFound(self.messageID)
        }
    }

    private func applyCachedRepliesAsync(
        pageSize: Int,
        preservingExisting: Bool = false
    ) async throws {
        guard let rootID = self.rootServerID else {
            self.replySnapshots = []
            self.nextReplyCursor = nil
            self.hasLoadedAllPreviousReplies = false
            self.hasAuthoritativeRemoteReplyPage = false
            self.publishReplies()
            return
        }
        guard let store = self.manager.store else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        let page = try await store.cachedRepliesAsync(
            messageID: rootID,
            pageSize: pageSize
        )
        try Task.checkCancellation()
        guard self.manager.store === store else { throw CancellationError() }
        self.applyCachedRepliesPage(page, preservingExisting: preservingExisting)
    }

    private func applyCachedRepliesPage(
        _ page: MessagingPage<MessagingMessageSnapshot>,
        preservingExisting: Bool
    ) {
        // A cache read suspends while GRDB works. Pagination may extend the
        // retained thread before it resumes, so a shorter result must merge
        // into that richer state instead of replacing it and regressing the
        // cursor. Preview reads still replace normally when their page covers
        // the complete retained preview.
        let cachePageCoversRetainedReplies = page.items.count >= self.replySnapshots.count
        let shouldPreserveExisting = preservingExisting || !cachePageCoversRetainedReplies
        self.replySnapshots = ParseMessagingControllerSupport.merge(
            shouldPreserveExisting ? self.replySnapshots : [],
            with: page.items
        )
        if cachePageCoversRetainedReplies,
           (!self.hasAuthoritativeRemoteReplyPage || page.hasMore) {
            self.nextReplyCursor = page.nextCursor
            self.hasLoadedAllPreviousReplies = !page.hasMore
        }
        self.publishReplies()
    }

    private func publishReplies() {
        let oldReplies = self.replies
        let newReplies = self.replySnapshots.map { ParseMessage(snapshot: $0) }
            .sorted { $0.createdAt > $1.createdAt }
        let changes = ParseListDiffer.changes(
            from: oldReplies,
            to: newReplies,
            identifiedBy: { $0.id },
            valuesEqual: ==
        )
        self.replies = newReplies
        if !changes.isEmpty {
            self.replyChangesSubject.send(changes)
        }
        if let rootSnapshot = self.message?.snapshot {
            self.updateRoot(with: rootSnapshot)
        }
    }

    private func updateRoot(with snapshot: MessagingMessageSnapshot) {
        let oldMessage = self.message
        let newMessage = ParseMessage(snapshot: snapshot, replies: self.replies)
        guard oldMessage != newMessage else { return }
        self.message = newMessage
        if oldMessage != nil {
            self.messageChangeSubject.send(.update(newMessage))
        } else {
            self.messageChangeSubject.send(.create(newMessage))
        }
    }

    nonisolated static func == (lhs: ParseMessageController, rhs: ParseMessageController) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
