//
//  ParseMessagingModels.swift
//  Jibber
//
//  Presentation adapters for the vendor-neutral MessagingContracts snapshots.
//

import Foundation
import MessagingContracts
import ParseCore
import UIKit

struct ParseConversationID: RawRepresentable, Codable, Hashable, Comparable,
                            CustomStringConvertible, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(cid rawValue: String) throws {
        guard !rawValue.isEmpty else {
            throw ParseMessagingCompatibilityError.invalidConversationID
        }
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }

    var description: String { self.rawValue }

    static func < (lhs: ParseConversationID, rhs: ParseConversationID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ParseConversationMember: @MainActor PersonType, Identifiable, Hashable {
    let snapshot: MessagingMemberSnapshot

    /// Matches Stream's member identity semantics for UI callers. Use
    /// `objectID` for mutations against ConversationMember itself.
    var id: String { self.snapshot.userID }
    var objectID: String { self.snapshot.objectID }
    var conversationID: ParseConversationID { ParseConversationID(self.snapshot.conversationID) }
    var userID: String { self.snapshot.userID }
    var role: MessagingMemberRole { self.snapshot.role }
    var joinedAt: Date { self.snapshot.joinedAt }
    var isActive: Bool { self.snapshot.isActive }
    var isHidden: Bool { self.snapshot.isHidden }
    var unreadCount: Int { self.snapshot.unreadCount }
    var lastReadMessageID: String? { self.snapshot.lastReadMessageID }
    var lastReadAt: Date? { self.snapshot.lastReadAt }
    var typingExpiresAt: Date? { self.snapshot.typingExpiresAt }
    var isCurrentUser: Bool {
        self.userID == User.current()?.objectId
    }
    @MainActor var person: PersonType? { ParsePeopleResolver.person(withID: self.userID) }
    @MainActor var name: String? { self.person?.fullName }
    var personId: String { self.userID }
    @MainActor var givenName: String { self.person?.givenName ?? "" }
    @MainActor var familyName: String { self.person?.familyName ?? "" }
    @MainActor var handle: String { self.person?.handle ?? "" }
    @MainActor var focusStatus: FocusStatus? { self.person?.focusStatus }
    @MainActor var phoneNumber: String? { self.person?.phoneNumber }
    @MainActor var updatedAt: Date? { self.person?.updatedAt }
    @MainActor var image: UIImage? { self.person?.image }

    func isTyping(at date: Date = Date()) -> Bool {
        self.snapshot.isTyping(at: date)
    }
}

struct ParsePinnedMessageAuthor {
    let personID: String?

    @MainActor var person: PersonType? {
        self.personID.flatMap(ParsePeopleResolver.person(withID:))
    }
    @MainActor var isCurrentUser: Bool {
        self.personID == ParseMessagingManager.shared.authenticatedUserID
    }
}

struct ParseMessagePinDetails {
    let pinnedAt: Date
    let pinnedBy: ParsePinnedMessageAuthor
}

struct ParseMessage: @MainActor Messageable, Identifiable, Hashable {
    let snapshot: MessagingMessageSnapshot
    private let loadedReplies: [ParseMessage]

    init(snapshot: MessagingMessageSnapshot, replies: [ParseMessage] = []) {
        self.snapshot = snapshot
        self.loadedReplies = replies.sorted { $0.createdAt > $1.createdAt }
    }

    /// Stable across the optimistic-to-confirmed transition. Use `serverID`
    /// for mutations that require a Parse object id.
    var id: String { self.snapshot.stableID }
    var serverID: String? { self.snapshot.objectID }
    var canonicalID: String { self.snapshot.canonicalMessageID }
    var text: String { self.snapshot.content.text ?? "" }
    var parentMessageId: String? { self.snapshot.replyToMessageID }
    var conversationId: String { self.snapshot.conversationID }
    var createdAt: Date { self.snapshot.sortDate }
    var authorId: String { self.snapshot.authorID }
    var isFromCurrentUser: Bool {
        self.authorId == User.current()?.objectId
    }
    @MainActor var person: PersonType? { ParsePeopleResolver.person(withID: self.authorId) }

    var attributes: [String: Any]? {
        guard !self.snapshot.content.attributes.isEmpty else { return nil }
        return self.snapshot.content.attributes
    }

    var deliveryStatus: DeliveryStatus {
        switch self.snapshot.localState {
        case .queued, .uploading, .sending, .retrying:
            return .sending
        case .failed:
            return .error
        case .confirmed:
            return self.nonMeReadReceipts.isEmpty ? .sent : .read
        }
    }

    var deliveryType: MessageDeliveryType {
        MessageDeliveryType(rawValue: self.snapshot.deliveryKind.rawValue) ?? .respectful
    }

    var isConsumedByMe: Bool {
        self.snapshot.receipts.contains {
            $0.userID == User.current()?.objectId && $0.state == .read
        }
    }

    @MainActor var hasBeenConsumedBy: [PersonType] {
        let ids = self.snapshot.receipts
            .filter { $0.state == .read }
            .map(\.userID)
        return ParsePeopleResolver.people(withIDs: ids)
    }

    var kind: MessageKind {
        let media = self.snapshot.content.attachments.compactMap(ParseRemoteMediaItem.init)
        let body = self.snapshot.content.text ?? ""

        if media.count > 1 {
            return .media(items: media, body: body)
        }
        if let item = media.first {
            switch item.type {
            case .photo:
                return .photo(photo: item, body: body)
            case .video:
                return .video(video: item, body: body)
            }
        }

        if let linkURL = self.snapshot.content.linkURL {
            return .link(url: linkURL, stringURL: body.isEmpty ? linkURL.absoluteString : body)
        }
        if self.snapshot.content.kind == .link,
           let linkURL = body.getURLs().first {
            return .link(url: linkURL, stringURL: body)
        }
        return .text(body)
    }

    var isDeleted: Bool { self.snapshot.isDeleted }
    var isPinned: Bool { self.snapshot.isPinned }
    var pinnedAt: Date? { self.snapshot.pinnedAt }
    var pinDetails: ParseMessagePinDetails? {
        guard self.snapshot.isPinned, let pinnedAt = self.snapshot.pinnedAt else { return nil }
        return ParseMessagePinDetails(
            pinnedAt: pinnedAt,
            pinnedBy: ParsePinnedMessageAuthor(personID: self.snapshot.pinnedByID)
        )
    }
    var localState: MessagingLocalMessageState { self.snapshot.localState }
    var lastFailureDescription: String? { self.snapshot.lastFailureDescription }
    var totalReplyCount: Int { max(self.snapshot.replyCount ?? 0, self.loadedReplies.count) }
    var replyCount: Int { self.totalReplyCount }
    @MainActor var recentReplies: [Messageable] { self.loadedReplies }
    var replies: [ParseMessage] { self.loadedReplies }
    var latestReplies: [ParseMessage] { self.loadedReplies }

    @MainActor var threadParticipants: [PersonType] {
        ParsePeopleResolver.people(withIDs: [self.authorId] + self.loadedReplies.map(\.authorId))
    }

    var lastUpdatedAt: Date? {
        let latestReceipt = self.snapshot.receipts.map(\.occurredAt).max()
        return [latestReceipt, self.snapshot.serverUpdatedAt, self.snapshot.editedAt, self.createdAt]
            .compactMap { $0 }
            .max()
    }

    var expressions: [ExpressionInfo] {
        self.snapshot.expressions.map {
            ExpressionInfo(authorId: $0.authorID, expressionId: $0.expressionID)
        }
    }

    @MainActor
    func setToConsumed() async {
        guard let messageID = self.serverID else { return }
        do {
            _ = try await ParseMessagingManager.shared.enqueue(
                .markRead(
                    conversationID: self.conversationId,
                    messageID: messageID,
                    messageCreatedAt: self.createdAt,
                    readAt: Date()
                )
            )
            await MainActor.run {
                UserNotificationManager.shared.handleRead(message: self.snapshot)
                NoticeStore.shared.removeNoticeIfNeccessary(for: self)
            }
        } catch {
            logError(error)
        }
    }

    func setToUnconsumed() async throws {
        guard let messageID = self.serverID else {
            throw ParseMessagingCompatibilityError.messageHasNotReachedServer(self.id)
        }
        _ = try await ParseMessagingManager.shared.enqueue(
            .markUnread(
                conversationID: self.conversationId,
                messageID: messageID,
                changedAt: Date()
            )
        )
    }

    func appendAttributes(with attributes: [String: Any]) async throws -> Messageable {
        throw ParseMessagingCompatibilityError.unsupportedAttributeMutation
    }

    private var nonMeReadReceipts: [MessagingReceiptSnapshot] {
        self.snapshot.receipts.filter {
            $0.state == .read && $0.userID != User.current()?.objectId
        }
    }

    static func == (lhs: ParseMessage, rhs: ParseMessage) -> Bool {
        lhs.snapshot == rhs.snapshot && lhs.loadedReplies == rhs.loadedReplies
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.snapshot)
        hasher.combine(self.loadedReplies)
    }
}

@MainActor
extension ParseMessage: MessageSequence {
    var updatedAt: Date { self.lastUpdatedAt ?? self.createdAt }
    var title: String? { nil }
    var messages: [Messageable] { self.loadedReplies }
}

struct ParseConversation: @MainActor MessageSequence, Identifiable, Hashable {
    let snapshot: MessagingConversationSnapshot
    let members: [ParseConversationMember]
    let parseMessages: [ParseMessage]
    let pinnedMessages: [ParseMessage]

    init(
        snapshot: MessagingConversationSnapshot,
        members: [ParseConversationMember] = [],
        messages: [ParseMessage] = [],
        pinnedMessages: [ParseMessage] = []
    ) {
        self.snapshot = snapshot
        self.members = members.sorted { $0.joinedAt < $1.joinedAt }
        self.parseMessages = messages.sorted { $0.createdAt > $1.createdAt }
        self.pinnedMessages = pinnedMessages.sorted {
            ($0.pinnedAt ?? $0.createdAt) > ($1.pinnedAt ?? $1.createdAt)
        }
    }

    var id: String { self.snapshot.id }
    var cid: ParseConversationID { ParseConversationID(self.id) }
    var conversationID: ParseConversationID { ParseConversationID(self.id) }
    var createdAt: Date { self.snapshot.createdAt ?? self.snapshot.lastActivityAt }
    var updatedAt: Date { self.snapshot.serverUpdatedAt ?? self.snapshot.lastActivityAt }
    var authorId: String { self.snapshot.creatorID }
    var kind: MessagingConversationKind { self.snapshot.kind }
    var isOwnedByMe: Bool {
        self.authorId == User.current()?.objectId
    }
    var isDeleted: Bool { self.snapshot.isDeleted }
    var activeMembers: [ParseConversationMember] { self.members.filter(\.isActive) }
    var lastActiveMembers: [ParseConversationMember] { self.activeMembers }
    var memberCount: Int { self.activeMembers.count }
    var latestMessages: [ParseMessage] { self.parseMessages }
    var currentMember: ParseConversationMember? { self.members.first(where: \.isCurrentUser) }
    var typingMembers: [ParseConversationMember] {
        self.activeMembers.filter { !$0.isCurrentUser && $0.isTyping() }
    }

    var attributes: [String: Any]? {
        ["kind": self.snapshot.kind.rawValue]
    }

    @MainActor var messages: [Messageable] { self.parseMessages }

    @MainActor var title: String? {
        if let explicitTitle = self.snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitTitle.isEmpty {
            return explicitTitle
        }

        let otherMembers = self.activeMembers.filter { !$0.isCurrentUser }
        if otherMembers.isEmpty {
            return "Just You"
        }
        let names = otherMembers.compactMap { member -> String? in
            guard let person = member.person else { return nil }
            return person.givenName.isEmpty ? person.fullName : person.givenName
        }
        if names.isEmpty {
            return "No Topic"
        }
        return names.joined(separator: ", ")
    }

    var totalUnread: Int {
        self.currentMember?.unreadCount ?? self.parseMessages.reduce(into: 0) { count, message in
            if !message.isFromCurrentUser && !message.isConsumedByMe && !message.isDeleted {
                count += 1
            }
        }
    }

    var expressions: [ExpressionInfo] {
        self.snapshot.expressions.map {
            ExpressionInfo(authorId: $0.authorID, expressionId: $0.expressionID)
        }
    }
}

enum ParseMessagingCompatibilityError: Error, LocalizedError {
    case invalidConversationID
    case messageHasNotReachedServer(String)
    case messageNotFound(String)
    case missingCurrentMember
    case missingCurrentUser
    case missingExpressionID
    case missingMediaURL
    case messagingNotInitialized
    case unsupportedAttributeMutation
    case unsupportedMessageKind(String)

    var errorDescription: String? {
        switch self {
        case .invalidConversationID:
            return "The conversation ID is invalid."
        case .messageHasNotReachedServer(let id):
            return "Message \(id) has not reached the server yet."
        case .messageNotFound(let id):
            return "Message \(id) is not loaded."
        case .missingCurrentMember:
            return "The current conversation membership is not loaded."
        case .missingCurrentUser:
            return "A signed-in user is required for messaging."
        case .missingExpressionID:
            return "The expression could not be saved."
        case .missingMediaURL:
            return "This media item does not have a local or remote URL."
        case .messagingNotInitialized:
            return "Parse messaging has not been initialized."
        case .unsupportedAttributeMutation:
            return "Arbitrary message attribute updates are not supported by Parse messaging."
        case .unsupportedMessageKind(let kind):
            return "Parse messaging does not support \(kind) messages."
        }
    }
}

@MainActor
private enum ParsePeopleResolver {
    static func person(withID id: String) -> PersonType? {
        if let current = User.current(), current.objectId == id {
            return current
        }
        return PeopleStore.shared.usersArray.first { $0.objectId == id }
    }

    static func people(withIDs ids: [String]) -> [PersonType] {
        var seen: Set<String> = []
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return self.person(withID: id)
        }
    }
}

private struct ParseRemoteMediaItem: MediaItem {
    let url: URL?
    let previewURL: URL?
    let image: UIImage? = nil
    let size: CGSize
    let fileName: String
    let type: MediaType
    let data: Data? = nil

    init?(_ attachment: MessagingAttachmentSnapshot) {
        switch attachment.kind {
        case .image:
            self.type = .photo
        case .video:
            self.type = .video
        case .file, .linkPreview:
            return nil
        }
        self.url = attachment.remoteURL ?? attachment.localURL
        self.previewURL = attachment.thumbnailURL
        self.size = CGSize(
            width: attachment.pixelWidth ?? 0,
            height: attachment.pixelHeight ?? 0
        )
        self.fileName = attachment.fileName ?? attachment.id
    }
}
