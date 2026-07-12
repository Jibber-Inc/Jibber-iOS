//
//  MessagingModels.swift
//  MessagingContracts
//
//  Vendor-neutral messaging values shared by the Parse transport, local cache,
//  outbox, and presentation adapters.
//

import Foundation

public typealias MessagingConversationID = String
public typealias MessagingMessageID = String
public typealias MessagingUserID = String

public enum MessagingConversationKind: String, Codable, CaseIterable, Hashable {
    case direct
    case group
    case moment
    case welcome
    case pass
}

public enum MessagingMemberRole: String, Codable, CaseIterable, Hashable {
    case owner
    case admin
    case member
}

public enum MessagingDeliveryKind: String, Codable, CaseIterable, Hashable {
    case timeSensitive = "time-sensitive"
    case conversational
    case respectful
}

public enum MessagingContentKind: String, Codable, CaseIterable, Hashable {
    case text
    case image
    case video
    case media
    case link
    case system
    case moment
}

public enum MessagingAttachmentKind: String, Codable, CaseIterable, Hashable {
    case image
    case video
    case file
    case linkPreview
}

public enum MessagingReceiptState: String, Codable, CaseIterable, Hashable {
    case sent
    case delivered
    case read
}

public struct MessagingExpressionReference: Codable, Hashable {
    public var authorID: MessagingUserID
    public var expressionID: String

    public init(authorID: MessagingUserID, expressionID: String) {
        self.authorID = authorID
        self.expressionID = expressionID
    }

    private enum CodingKeys: String, CodingKey {
        case authorID = "authorId"
        case expressionID = "expressionId"
    }
}

/// Local-only delivery state. The server never needs to trust this value.
public enum MessagingLocalMessageState: String, Codable, CaseIterable, Hashable {
    case confirmed
    case queued
    case uploading
    case sending
    case retrying
    case failed
}

public struct MessagingAttachmentSnapshot: Codable, Hashable {
    public var id: String
    public var kind: MessagingAttachmentKind
    public var localURL: URL?
    public var remoteURL: URL?
    public var thumbnailURL: URL?
    public var fileName: String?
    public var mimeType: String?
    public var byteCount: Int?
    public var pixelWidth: Double?
    public var pixelHeight: Double?
    public var duration: TimeInterval?

    public init(
        id: String = UUID().uuidString,
        kind: MessagingAttachmentKind,
        localURL: URL? = nil,
        remoteURL: URL? = nil,
        thumbnailURL: URL? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        byteCount: Int? = nil,
        pixelWidth: Double? = nil,
        pixelHeight: Double? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.kind = kind
        self.localURL = localURL
        self.remoteURL = remoteURL
        self.thumbnailURL = thumbnailURL
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
    }

    public var requiresUpload: Bool {
        localURL != nil && remoteURL == nil && kind != .linkPreview
    }
}

public struct MessagingMessageContent: Codable, Hashable {
    public var kind: MessagingContentKind
    public var text: String?
    public var linkURL: URL?
    public var attachments: [MessagingAttachmentSnapshot]
    public var attributes: [String: String]

    public init(
        kind: MessagingContentKind,
        text: String? = nil,
        linkURL: URL? = nil,
        attachments: [MessagingAttachmentSnapshot] = [],
        attributes: [String: String] = [:]
    ) {
        self.kind = kind
        self.text = text
        self.linkURL = linkURL
        self.attachments = attachments
        self.attributes = attributes
    }

    public var isEmpty: Bool {
        let hasText = !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return !hasText && linkURL == nil && attachments.isEmpty && attributes.isEmpty
    }
}

/// Input for an idempotent send. Reusing `clientMessageID` intentionally reuses
/// the same optimistic row and remote write.
public struct MessagingMessageDraft: Codable, Hashable {
    public var conversationID: MessagingConversationID
    public var clientMessageID: String
    public var clientCreatedAt: Date
    public var content: MessagingMessageContent
    public var replyToMessageID: MessagingMessageID?
    public var deliveryKind: MessagingDeliveryKind
    public var expressions: [MessagingExpressionReference]

    public init(
        conversationID: MessagingConversationID,
        clientMessageID: String = UUID().uuidString.lowercased(),
        clientCreatedAt: Date = Date(),
        content: MessagingMessageContent,
        replyToMessageID: MessagingMessageID? = nil,
        deliveryKind: MessagingDeliveryKind = .conversational,
        expressions: [MessagingExpressionReference] = []
    ) {
        self.conversationID = conversationID
        self.clientMessageID = clientMessageID
        self.clientCreatedAt = clientCreatedAt
        self.content = content
        self.replyToMessageID = replyToMessageID
        self.deliveryKind = deliveryKind
        self.expressions = expressions
    }
}

public struct MessagingReactionSnapshot: Codable, Hashable {
    public var objectID: String?
    public var messageID: MessagingMessageID
    public var userID: MessagingUserID
    public var type: String
    public var createdAt: Date
    public var isDeleted: Bool
    public var deletedAt: Date?

    public init(
        objectID: String? = nil,
        messageID: MessagingMessageID,
        userID: MessagingUserID,
        type: String,
        createdAt: Date,
        isDeleted: Bool? = nil,
        deletedAt: Date? = nil
    ) {
        self.objectID = objectID
        self.messageID = messageID
        self.userID = userID
        self.type = type
        self.createdAt = createdAt
        self.isDeleted = isDeleted ?? (deletedAt != nil)
        self.deletedAt = deletedAt
    }
}

public struct MessagingReceiptSnapshot: Codable, Hashable {
    public var objectID: String?
    public var messageID: MessagingMessageID
    public var userID: MessagingUserID
    public var state: MessagingReceiptState
    public var occurredAt: Date

    public init(
        objectID: String? = nil,
        messageID: MessagingMessageID,
        userID: MessagingUserID,
        state: MessagingReceiptState,
        occurredAt: Date
    ) {
        self.objectID = objectID
        self.messageID = messageID
        self.userID = userID
        self.state = state
        self.occurredAt = occurredAt
    }
}

public struct MessagingMessageSnapshot: Codable, Hashable, Identifiable {
    public var objectID: String?
    public var clientMessageID: String
    public var conversationID: MessagingConversationID
    public var authorID: MessagingUserID
    public var clientCreatedAt: Date
    public var serverCreatedAt: Date?
    public var serverUpdatedAt: Date?
    public var content: MessagingMessageContent
    public var replyToMessageID: MessagingMessageID?
    public var replyCount: Int?
    public var deliveryKind: MessagingDeliveryKind
    public var editedAt: Date?
    public var isPinned: Bool
    public var pinnedAt: Date?
    public var pinnedByID: MessagingUserID?
    public var isDeleted: Bool
    public var deletedAt: Date?
    public var reactions: [MessagingReactionSnapshot]
    public var receipts: [MessagingReceiptSnapshot]
    public var expressions: [MessagingExpressionReference]
    public var localState: MessagingLocalMessageState
    public var lastFailureDescription: String?

    public init(
        objectID: String? = nil,
        clientMessageID: String,
        conversationID: MessagingConversationID,
        authorID: MessagingUserID,
        clientCreatedAt: Date,
        serverCreatedAt: Date? = nil,
        serverUpdatedAt: Date? = nil,
        content: MessagingMessageContent,
        replyToMessageID: MessagingMessageID? = nil,
        replyCount: Int? = nil,
        deliveryKind: MessagingDeliveryKind,
        editedAt: Date? = nil,
        isPinned: Bool? = nil,
        pinnedAt: Date? = nil,
        pinnedByID: MessagingUserID? = nil,
        isDeleted: Bool? = nil,
        deletedAt: Date? = nil,
        reactions: [MessagingReactionSnapshot] = [],
        receipts: [MessagingReceiptSnapshot] = [],
        expressions: [MessagingExpressionReference] = [],
        localState: MessagingLocalMessageState,
        lastFailureDescription: String? = nil
    ) {
        self.objectID = objectID
        self.clientMessageID = clientMessageID
        self.conversationID = conversationID
        self.authorID = authorID
        self.clientCreatedAt = clientCreatedAt
        self.serverCreatedAt = serverCreatedAt
        self.serverUpdatedAt = serverUpdatedAt
        self.content = content
        self.replyToMessageID = replyToMessageID
        self.replyCount = replyCount
        self.deliveryKind = deliveryKind
        self.editedAt = editedAt
        self.isPinned = isPinned ?? (pinnedAt != nil)
        self.pinnedAt = pinnedAt
        self.pinnedByID = pinnedByID
        self.isDeleted = isDeleted ?? (deletedAt != nil)
        self.deletedAt = deletedAt
        self.reactions = reactions
        self.receipts = receipts
        self.expressions = expressions
        self.localState = localState
        self.lastFailureDescription = lastFailureDescription
    }

    /// Stable across the optimistic-to-confirmed transition.
    public var id: String { clientMessageID }

    public var stableID: String { clientMessageID }

    public var canonicalMessageID: String { objectID ?? clientMessageID }

    public var sortDate: Date { serverCreatedAt ?? clientCreatedAt }

}

public struct MessagingConversationSnapshot: Codable, Hashable, Identifiable {
    public var id: MessagingConversationID
    public var createdAt: Date?
    public var clientConversationID: String?
    public var contextKey: String?
    public var kind: MessagingConversationKind
    public var title: String?
    public var creatorID: MessagingUserID
    public var membershipRevision: Int
    public var latestMessageID: MessagingMessageID?
    public var latestMessageText: String?
    public var lastActivityAt: Date
    public var serverUpdatedAt: Date?
    public var expressions: [MessagingExpressionReference]
    public var isDeleted: Bool
    public var deletedAt: Date?

    public init(
        id: MessagingConversationID,
        createdAt: Date? = nil,
        clientConversationID: String? = nil,
        contextKey: String? = nil,
        kind: MessagingConversationKind,
        title: String? = nil,
        creatorID: MessagingUserID,
        membershipRevision: Int = 0,
        latestMessageID: MessagingMessageID? = nil,
        latestMessageText: String? = nil,
        lastActivityAt: Date,
        serverUpdatedAt: Date? = nil,
        expressions: [MessagingExpressionReference] = [],
        isDeleted: Bool? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.clientConversationID = clientConversationID
        self.contextKey = contextKey
        self.kind = kind
        self.title = title
        self.creatorID = creatorID
        self.membershipRevision = membershipRevision
        self.latestMessageID = latestMessageID
        self.latestMessageText = latestMessageText
        self.lastActivityAt = lastActivityAt
        self.serverUpdatedAt = serverUpdatedAt
        self.expressions = expressions
        self.isDeleted = isDeleted ?? (deletedAt != nil)
        self.deletedAt = deletedAt
    }
}

public struct MessagingMemberSnapshot: Codable, Hashable, Identifiable {
    public var objectID: String
    public var conversationID: MessagingConversationID
    public var userID: MessagingUserID
    public var role: MessagingMemberRole
    public var joinedAt: Date
    public var active: Bool
    public var leftAt: Date?
    public var notificationsEnabled: Bool
    public var isHidden: Bool
    public var hiddenAt: Date?
    public var unreadCount: Int
    public var lastReadMessageID: MessagingMessageID?
    public var lastReadAt: Date?
    public var typingExpiresAt: Date?

    public init(
        objectID: String,
        conversationID: MessagingConversationID,
        userID: MessagingUserID,
        role: MessagingMemberRole,
        joinedAt: Date,
        active: Bool? = nil,
        leftAt: Date? = nil,
        notificationsEnabled: Bool = true,
        isHidden: Bool = false,
        hiddenAt: Date? = nil,
        unreadCount: Int = 0,
        lastReadMessageID: MessagingMessageID? = nil,
        lastReadAt: Date? = nil,
        typingExpiresAt: Date? = nil
    ) {
        self.objectID = objectID
        self.conversationID = conversationID
        self.userID = userID
        self.role = role
        self.joinedAt = joinedAt
        self.active = active ?? (leftAt == nil)
        self.leftAt = leftAt
        self.notificationsEnabled = notificationsEnabled
        self.isHidden = isHidden
        self.hiddenAt = hiddenAt
        self.unreadCount = unreadCount
        self.lastReadMessageID = lastReadMessageID
        self.lastReadAt = lastReadAt
        self.typingExpiresAt = typingExpiresAt
    }

    public var id: String { objectID }
    public var isActive: Bool { active && leftAt == nil }

    public func isTyping(at date: Date = Date()) -> Bool {
        isActive && (typingExpiresAt.map { $0 > date } ?? false)
    }

    private enum CodingKeys: String, CodingKey {
        case objectID
        case conversationID
        case userID
        case role
        case joinedAt
        case active
        case leftAt
        case notificationsEnabled
        case isHidden
        case hiddenAt
        case unreadCount
        case lastReadMessageID
        case lastReadAt
        case typingExpiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectID = try container.decode(String.self, forKey: .objectID)
        conversationID = try container.decode(String.self, forKey: .conversationID)
        userID = try container.decode(String.self, forKey: .userID)
        role = try container.decode(MessagingMemberRole.self, forKey: .role)
        joinedAt = try container.decode(Date.self, forKey: .joinedAt)
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
        leftAt = try container.decodeIfPresent(Date.self, forKey: .leftAt)
        notificationsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .notificationsEnabled
        ) ?? true
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        hiddenAt = try container.decodeIfPresent(Date.self, forKey: .hiddenAt)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        lastReadMessageID = try container.decodeIfPresent(
            String.self,
            forKey: .lastReadMessageID
        )
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        typingExpiresAt = try container.decodeIfPresent(Date.self, forKey: .typingExpiresAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(objectID, forKey: .objectID)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(userID, forKey: .userID)
        try container.encode(role, forKey: .role)
        try container.encode(joinedAt, forKey: .joinedAt)
        try container.encode(active, forKey: .active)
        try container.encodeIfPresent(leftAt, forKey: .leftAt)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encodeIfPresent(hiddenAt, forKey: .hiddenAt)
        try container.encode(unreadCount, forKey: .unreadCount)
        try container.encodeIfPresent(lastReadMessageID, forKey: .lastReadMessageID)
        try container.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
        try container.encodeIfPresent(typingExpiresAt, forKey: .typingExpiresAt)
    }
}

public enum MessagingModelError: Error, Equatable {
    case missingField(className: String, field: String)
    case invalidDraft(String)
    case identityMismatch(expected: String, actual: String?)
}
