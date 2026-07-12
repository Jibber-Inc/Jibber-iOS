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
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTask: Task<Void, Never>?

    init(
        conversationID: ParseConversationID,
        messageID: String,
        manager: ParseMessagingManager,
        automaticallySynchronize: Bool = true
    ) {
        self.conversationID = conversationID
        self.messageID = messageID
        self.manager = manager
        self.conversationController = ParseConversationController(
            conversationID: conversationID,
            manager: manager,
            automaticallySynchronize: false
        )
        self.observeState()
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

    static func controller(for message: Messageable) -> ParseMessageController? {
        guard !message.conversationId.isEmpty, !message.id.isEmpty else { return nil }
        return ParseMessageController(
            conversationID: message.conversationId,
            messageID: message.id
        )
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
        try self.applyCachedReplies(pageSize: pageSize)

        guard let rootID = self.rootServerID else {
            // Optimistic roots cannot have server replies yet.
            return
        }
        _ = try await self.manager.replies(messageID: rootID, pageSize: pageSize)
        try self.applyCachedReplies(pageSize: max(pageSize, self.replySnapshots.count + 1))
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
           let cached = try self.manager.store?.cachedMessage(objectID: rootID) {
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
        try self.applyCachedReplies(pageSize: max(50, self.replySnapshots.count + 10))
        return id
    }

    func editMessage(with sendable: MessageSendable) async throws {
        guard case .text(let text) = sendable.kind else {
            throw ParseMessagingCompatibilityError.unsupportedMessageKind("edited non-text")
        }
        try self.conversationController.editMessage(messageID: self.messageID, text: text)
    }

    func editMessage(text: String) throws {
        try self.conversationController.editMessage(messageID: self.messageID, text: text)
    }

    func deleteMessage() throws {
        try self.conversationController.deleteMessage(self.messageID)
    }

    func retryFailedMessage() throws {
        try self.conversationController.retryFailedMessage(self.messageID)
    }

    func cancelFailedMessage() throws {
        try self.conversationController.cancelFailedMessage(self.messageID)
    }

    func pinMessage() throws {
        try self.conversationController.pinMessage(self.messageID)
    }

    func unpinMessage() throws {
        try self.conversationController.unpinMessage(self.messageID)
    }

    func setReaction(_ type: String, selected: Bool) throws {
        try self.conversationController.setReaction(type, selected: selected, messageID: self.messageID)
    }

    func markRead() throws {
        try self.conversationController.markRead(self.messageID)
    }

    func markUnread() throws {
        try self.conversationController.markUnread(self.messageID)
    }

    func setTyping(_ isTyping: Bool) throws {
        try self.conversationController.setTyping(isTyping)
    }

    func add(expression: Expression) async throws {
        guard let rootID = self.rootServerID,
              let authorID = User.current()?.objectId else {
            throw ParseMessagingCompatibilityError.messageHasNotReachedServer(self.messageID)
        }
        let saved = try await expression.saveToServer()
        guard let expressionID = saved.objectId else {
            throw ParseMessagingCompatibilityError.missingExpressionID
        }
        try self.manager.enqueue(
            .addMessageExpression(
                conversationID: self.conversationID.rawValue,
                messageID: rootID,
                reference: MessagingExpressionReference(
                    authorID: authorID,
                    expressionID: expressionID
                )
            )
        )
        await ToastScheduler.shared.schedule(
            toastType: .success(ImageSymbol.faceSmiling, "Expression added")
        )
    }

    func updateTitle(_ title: String) throws {
        try self.conversationController.updateTitle(title)
    }

    func setMemberActive(userID: String, active: Bool) throws {
        try self.conversationController.setMemberActive(userID: userID, active: active)
    }

    func hideConversation() throws {
        try self.conversationController.hideConversation()
    }

    func showConversation() throws {
        try self.conversationController.showConversation()
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
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.rootServerID != nil else { return }
                    do {
                        try self.applyCachedReplies(
                            pageSize: max(50, self.replySnapshots.count + 10)
                        )
                    } catch {
                        logError(error)
                    }
                }
            }
            .store(in: &self.cancellables)
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

    private func applyCachedReplies(pageSize: Int) throws {
        guard let rootID = self.rootServerID else {
            self.replySnapshots = []
            self.nextReplyCursor = nil
            self.publishReplies()
            return
        }
        let page = try ParseMessagingControllerSupport.cachedReplies(
            messageID: rootID,
            pageSize: pageSize,
            manager: self.manager
        )
        self.replySnapshots = ParseMessagingControllerSupport.merge([], with: page.items)
        self.nextReplyCursor = page.nextCursor
        self.hasLoadedAllPreviousReplies = !page.hasMore
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
