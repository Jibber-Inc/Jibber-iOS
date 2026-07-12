//
//  ParseConversationController.swift
//  Jibber
//

import Combine
import Foundation
import MessagingContracts
import MessagingPersistence
import ParseCore

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
    private var messagingChangeCancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var typingExpiryTask: Task<Void, Never>?

    init(
        conversationID: ParseConversationID,
        manager: ParseMessagingManager,
        automaticallySynchronize: Bool = true
    ) {
        self.conversationID = conversationID
        self.manager = manager
        self.observeMessagingChanges()
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
        ParseConversationController(conversationID: conversationID)
    }

    static func controller(for conversation: ParseConversation) -> ParseConversationController {
        ParseConversationController(conversationID: conversation.id)
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

    func messageController(for messageID: String) -> ParseMessageController {
        ParseMessageController(
            conversationID: self.conversationID,
            messageID: messageID,
            manager: self.manager
        )
    }

    // MARK: - Reads

    func synchronize(pageSize: Int = 50) async throws {
        try self.applyCachedState(pageSize: pageSize)
        guard self.manager.isInitialized,
              let repository = self.manager.repository,
              let store = self.manager.store else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }

        let conversation = try await repository.conversation(id: self.conversationID.rawValue)
        try store.upsert(conversations: [conversation])
        _ = try await self.manager.members(conversationID: self.conversationID.rawValue)
        _ = try await self.manager.messages(
            conversationID: self.conversationID.rawValue,
            pageSize: pageSize
        )
        _ = try await self.manager.pinnedMessages(
            conversationID: self.conversationID.rawValue
        )
        try self.applyCachedState(pageSize: max(pageSize, self.allSnapshots.count + 1))
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
        try self.publishCurrentState()
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
        try self.publishCurrentState()
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

    func getMostRecentMessage(fromCurrentUser: Bool) -> ParseMessage? {
        self.parseMessages.first { $0.isFromCurrentUser == fromCurrentUser }
    }

    // MARK: - Writes

    @discardableResult
    func createNewMessage(with sendable: MessageSendable) async throws -> String {
        let draft = try await ParseMessageDraftTranslator.draft(
            from: sendable,
            conversationID: self.conversationID
        )
        let staged = try self.manager.send(draft)
        self.allSnapshots = ParseMessagingControllerSupport.merge(
            self.allSnapshots,
            with: [staged]
        )
        try self.publishCurrentState()
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
        let rootID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        let draft = try await ParseMessageDraftTranslator.draft(
            from: sendable,
            conversationID: self.conversationID,
            replyToMessageID: rootID
        )
        let staged = try self.manager.send(draft)
        self.allSnapshots = ParseMessagingControllerSupport.merge(
            self.allSnapshots,
            with: [staged]
        )
        try self.publishCurrentState()
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
        try self.editMessage(messageID: previousMessage.id, text: text)
    }

    func editMessage(messageID: String, text: String) throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try self.queue(
            .edit(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                text: text,
                editedAt: Date()
            )
        )
    }

    func deleteMessage(_ messageID: String) throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try self.queue(
            .delete(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                deletedAt: Date()
            )
        )
    }

    func retryFailedMessage(_ messageID: String) throws {
        guard let snapshot = self.allSnapshots.first(where: {
            $0.stableID == messageID || $0.objectID == messageID
        }) else {
            throw ParseMessagingCompatibilityError.messageNotFound(messageID)
        }
        try self.manager.retryBlockedOperation(
            idempotencyKey: snapshot.clientMessageID
        )
    }

    func cancelFailedMessage(_ messageID: String) throws {
        guard let snapshot = self.allSnapshots.first(where: {
            $0.stableID == messageID || $0.objectID == messageID
        }) else {
            throw ParseMessagingCompatibilityError.messageNotFound(messageID)
        }
        try self.manager.cancelBlockedOperation(
            idempotencyKey: snapshot.clientMessageID
        )
    }

    func pinMessage(_ messageID: String) throws {
        try self.setPinned(true, messageID: messageID)
    }

    func unpinMessage(_ messageID: String) throws {
        try self.setPinned(false, messageID: messageID)
    }

    func setReaction(_ type: String, selected: Bool, messageID: String) throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try self.queue(
            .setReaction(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                type: type,
                isSelected: selected
            )
        )
    }

    func markRead(_ messageID: String) throws {
        guard let snapshot = self.allSnapshots.first(where: {
            $0.stableID == messageID || $0.objectID == messageID
        }), let serverID = snapshot.objectID else {
            throw ParseMessagingCompatibilityError.messageNotFound(messageID)
        }
        try self.queue(
            .markRead(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                messageCreatedAt: snapshot.sortDate,
                readAt: Date()
            )
        )
    }

    func markUnread(_ messageID: String) throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try self.queue(
            .markUnread(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                changedAt: Date()
            )
        )
    }

    func updateTitle(_ title: String) throws {
        try self.queue(
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
        do {
            if let name = name {
                try self.updateTitle(name)
            }
            completion?(nil)
        } catch {
            completion?(error)
        }
    }

    func deleteConversation() throws {
        try self.queue(
            .setConversationDeleted(
                conversationID: self.conversationID.rawValue,
                isDeleted: true,
                changedAt: Date()
            )
        )
    }

    func deleteChannel() async throws {
        try self.deleteConversation()
    }

    func setMemberActive(userID: String, active: Bool) throws {
        try self.queue(
            .setMemberActive(
                conversationID: self.conversationID.rawValue,
                userID: userID,
                active: active
            )
        )
    }

    func addMembers(userIDs: Set<String>) throws {
        try userIDs.forEach { try self.setMemberActive(userID: $0, active: true) }
    }

    func addMembers(userIds: Set<String>) async throws {
        try self.addMembers(userIDs: userIds)
    }

    func addMembers(userIds: Set<String>, completion: ((Error?) -> Void)? = nil) {
        do {
            try self.addMembers(userIDs: userIds)
            completion?(nil)
        } catch {
            completion?(error)
        }
    }

    func removeMembers(userIDs: Set<String>) throws {
        try userIDs.forEach { try self.setMemberActive(userID: $0, active: false) }
    }

    func removeMembers(userIds: Set<String>) async throws {
        try self.removeMembers(userIDs: userIds)
    }

    func hideConversation() throws {
        let member = try ParseMessagingControllerSupport.currentMember(in: self.members)
        try self.setHidden(true, memberID: member.objectID)
    }

    func hideChannel(clearHistory: Bool = false) async throws {
        // Parse keeps tombstones/history server-side; clearHistory is
        // intentionally ignored instead of destructively deleting local data.
        try self.hideConversation()
    }

    func showConversation() throws {
        let member = try ParseMessagingControllerSupport.currentMember(in: self.members)
        try self.setHidden(false, memberID: member.objectID)
    }

    func showChannel() async throws {
        try self.showConversation()
    }

    func markRead() async throws {
        guard let newestUnread = self.parseMessages.first(where: {
            !$0.isFromCurrentUser && !$0.isConsumedByMe && !$0.isDeleted
        }) else { return }
        try self.markRead(newestUnread.id)
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
        let saved = try await expression.saveToServer()
        guard let expressionID = saved.objectId,
              let authorID = User.current()?.objectId else {
            throw ParseMessagingCompatibilityError.missingExpressionID
        }
        try self.queue(
            .addConversationExpression(
                conversationID: self.conversationID.rawValue,
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

    // MARK: - State publication

    private func observeMessagingChanges() {
        self.messagingChangeCancellable = NotificationCenter.default
            .publisher(for: .parseMessagingDidChange, object: self.manager)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try self.applyCachedState(
                            pageSize: max(50, self.allSnapshots.count + 10)
                        )
                    } catch {
                        logError(error)
                    }
                }
            }
    }

    private func applyCachedState(pageSize: Int) throws {
        guard let store = self.manager.store else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        let page = try store.cachedMessages(
            conversationID: self.conversationID.rawValue,
            before: nil,
            pageSize: pageSize
        )
        self.allSnapshots = ParseMessagingControllerSupport.merge([], with: page.items)
        self.nextMessageCursor = page.nextCursor
        self.hasLoadedAllPreviousMessages = !page.hasMore
        try self.publishCurrentState()
    }

    private func publishCurrentState() throws {
        let oldMessages = self.parseMessages
        let newMessages = ParseMessagingControllerSupport.rootMessages(from: self.allSnapshots)
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

        let oldMembers = self.members
        let memberSnapshots = try ParseMessagingControllerSupport.cachedMembers(
            conversationID: self.conversationID.rawValue,
            manager: self.manager
        )
        let newMembers = memberSnapshots.map(ParseConversationMember.init)
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

        let oldConversation = self.conversation
        let conversationSnapshot = try ParseMessagingControllerSupport.cachedConversation(
            id: self.conversationID.rawValue,
            manager: self.manager
        )
        let newConversation = conversationSnapshot.map {
            let pinnedMessages = (try? ParseMessagingControllerSupport.cachedPinnedMessages(
                conversationID: self.conversationID.rawValue,
                manager: self.manager
            ))?.map { ParseMessage(snapshot: $0) } ?? newMessages.filter(\.isPinned)
            return ParseConversation(
                snapshot: $0,
                members: newMembers,
                messages: newMessages,
                pinnedMessages: pinnedMessages
            )
        }
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

    private func setPinned(_ isPinned: Bool, messageID: String) throws {
        let serverID = try ParseMessagingControllerSupport.serverMessageID(
            for: messageID,
            in: self.allSnapshots
        )
        try self.queue(
            .setPinned(
                conversationID: self.conversationID.rawValue,
                messageID: serverID,
                isPinned: isPinned,
                changedAt: Date()
            )
        )
    }

    private func setHidden(_ isHidden: Bool, memberID: String) throws {
        try self.queue(
            .setMemberHidden(
                conversationID: self.conversationID.rawValue,
                memberID: memberID,
                isHidden: isHidden
            )
        )
    }

    private func queue(_ mutation: MessagingMutation) throws {
        try self.manager.enqueue(mutation)
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
