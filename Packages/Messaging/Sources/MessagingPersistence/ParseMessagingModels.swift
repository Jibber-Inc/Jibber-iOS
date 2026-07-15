//
//  ParseMessagingModels.swift
//  MessagingPersistence
//
//  ParseSwift wire models. Server-side CLPs, ACL rewriting, validation, and
//  compound indexes remain authoritative; clients never infer authorization
//  from these values.
//

import Foundation
import MessagingContracts
import ParseSwift

public struct MessagingParseUser: ParseUser, @unchecked Sendable {
    public var objectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var ACL: ParseACL?
    public var originalData: Data?

    public var username: String?
    public var email: String?
    public var emailVerified: Bool?
    public var password: String?
    public var authData: [String: [String: String]?]?

    public init() {}
}

public struct MessagingParseAttachment: Codable, Hashable, @unchecked Sendable {
    public var id: String?
    public var kind: MessagingAttachmentKind?
    public var file: ParseFile?
    public var thumbnail: ParseFile?
    public var fileName: String?
    public var mimeType: String?
    public var byteCount: Int?
    public var pixelWidth: Double?
    public var pixelHeight: Double?
    public var duration: TimeInterval?
    public var linkURL: String?

    public init(
        id: String? = nil,
        kind: MessagingAttachmentKind? = nil,
        file: ParseFile? = nil,
        thumbnail: ParseFile? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        byteCount: Int? = nil,
        pixelWidth: Double? = nil,
        pixelHeight: Double? = nil,
        duration: TimeInterval? = nil,
        linkURL: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.file = file
        self.thumbnail = thumbnail
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.linkURL = linkURL
    }
}

public struct MessagingParseMetadata: Codable, Equatable, Sendable {
    public let values: [String: String]

    public init(_ values: [String: String]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var values: [String: String] = [:]

        for key in container.allKeys {
            if try container.decodeNil(forKey: key) {
                continue
            } else if let value = try? container.decode(String.self, forKey: key) {
                values[key.stringValue] = value
            } else if let value = try? container.decode(Int.self, forKey: key) {
                values[key.stringValue] = String(value)
            } else if let value = try? container.decode(Double.self, forKey: key) {
                values[key.stringValue] = String(value)
            } else if let value = try? container.decode(Bool.self, forKey: key) {
                values[key.stringValue] = String(value)
            } else {
                throw DecodingError.typeMismatch(
                    String.self,
                    .init(
                        codingPath: decoder.codingPath + [key],
                        debugDescription: "Expected a string-compatible metadata value."
                    )
                )
            }
        }

        self.values = values
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in values {
            try container.encode(value, forKey: Key(stringValue: key))
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }
}

public struct MessagingParseConversation: ParseObject, @unchecked Sendable {
    public static var className: String { "Conversation" }

    public var objectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var ACL: ParseACL?
    public var originalData: Data?

    public var creator: Pointer<MessagingParseUser>?
    public var clientConversationId: String?
    public var contextKey: String?
    public var type: MessagingConversationKind?
    public var title: String?
    public var membershipRevision: Int?
    public var latestMessage: Pointer<MessagingParseMessage>?
    public var latestMessageAt: Date?
    public var latestMessageAuthor: Pointer<MessagingParseUser>?
    public var latestMessageText: String?
    public var lastActivityAt: Date?
    public var expressions: [MessagingExpressionReference]?
    public var isDeleted: Bool?
    public var deletedAt: Date?

    public init() {}
}

public struct MessagingParseConversationMember: ParseObject, @unchecked Sendable {
    public static var className: String { "ConversationMember" }

    public var objectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var ACL: ParseACL?
    public var originalData: Data?

    public var conversation: Pointer<MessagingParseConversation>?
    public var user: Pointer<MessagingParseUser>?
    public var role: MessagingMemberRole?
    public var joinedAt: Date?
    public var active: Bool?
    public var leftAt: Date?
    public var notificationsEnabled: Bool?
    public var isHidden: Bool?
    public var hiddenAt: Date?
    public var unreadCount: Int?
    public var lastReadMessage: Pointer<MessagingParseMessage>?
    public var lastReadAt: Date?
    public var typingExpiresAt: Date?

    public init() {}
}

public struct MessagingParseMessage: ParseObject, @unchecked Sendable {
    public static var className: String { "Message" }

    public var objectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var ACL: ParseACL?
    public var originalData: Data?

    public var conversation: Pointer<MessagingParseConversation>?
    public var author: Pointer<MessagingParseUser>?
    /// Unique per author. The backend must enforce a compound unique index and
    /// return the existing message when a retry uses the same value.
    public var clientMessageId: String?
    public var clientCreatedAt: Date?
    public var contentType: MessagingContentKind?
    public var text: String?
    public var linkURL: String?
    public var attachments: [MessagingParseAttachment]?
    public var metadata: MessagingParseMetadata?
    public var replyTo: Pointer<MessagingParseMessage>?
    public var replyCount: Int?
    public var latestReply: Pointer<MessagingParseMessage>?
    public var latestReplyAt: Date?
    public var latestReplyAuthor: Pointer<MessagingParseUser>?
    public var latestReplyText: String?
    public var deliveryType: MessagingDeliveryKind?
    public var editedAt: Date?
    public var expressions: [MessagingExpressionReference]?
    public var isPinned: Bool?
    public var pinnedAt: Date?
    public var pinnedBy: Pointer<MessagingParseUser>?
    public var isDeleted: Bool?
    public var deletedAt: Date?
    public var attachmentsPurgedAt: Date?

    public init() {}
}

public struct MessagingParseReaction: ParseObject, @unchecked Sendable {
    public static var className: String { "MessageReaction" }

    public var objectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var ACL: ParseACL?
    public var originalData: Data?

    public var message: Pointer<MessagingParseMessage>?
    public var conversation: Pointer<MessagingParseConversation>?
    public var user: Pointer<MessagingParseUser>?
    public var type: String?
    public var isDeleted: Bool?
    public var deletedAt: Date?

    public init() {}
}

public struct MessagingParseReceipt: ParseObject, @unchecked Sendable {
    public static var className: String { "MessageReceipt" }

    public var objectId: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var ACL: ParseACL?
    public var originalData: Data?

    public var message: Pointer<MessagingParseMessage>?
    public var conversation: Pointer<MessagingParseConversation>?
    public var user: Pointer<MessagingParseUser>?
    public var state: MessagingReceiptState?
    public var messageCreatedAt: Date?
    public var deliveredAt: Date?
    public var readAt: Date?

    public init() {}
}

public extension MessagingParseAttachment {
    init(
        snapshot: MessagingAttachmentSnapshot,
        uploadedFile: ParseFile?,
        uploadedThumbnail: ParseFile? = nil
    ) {
        self.init(
            id: snapshot.id,
            kind: snapshot.kind,
            file: uploadedFile,
            thumbnail: uploadedThumbnail,
            fileName: snapshot.fileName,
            mimeType: snapshot.mimeType,
            byteCount: snapshot.byteCount,
            pixelWidth: snapshot.pixelWidth,
            pixelHeight: snapshot.pixelHeight,
            duration: snapshot.duration,
            linkURL: snapshot.kind == .linkPreview ? snapshot.remoteURL?.absoluteString : nil
        )
    }

    func snapshot() throws -> MessagingAttachmentSnapshot {
        guard let kind = kind else {
            throw MessagingModelError.missingField(className: "Message.Attachment", field: "kind")
        }
        let remoteURL = file?.url ?? linkURL.flatMap(URL.init(string:))
        let stableID = id
            ?? remoteURL?.absoluteString
            ?? fileName
            ?? "\(kind.rawValue)-attachment"
        return MessagingAttachmentSnapshot(
            id: stableID,
            kind: kind,
            remoteURL: remoteURL,
            thumbnailURL: thumbnail?.url,
            fileName: fileName,
            mimeType: mimeType,
            byteCount: byteCount,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            duration: duration
        )
    }
}

public extension MessagingParseMessage {
    init(
        draft: MessagingMessageDraft,
        authorID: MessagingUserID,
        uploadedAttachments: [MessagingParseAttachment]
    ) {
        self.init()
        conversation = Pointer<MessagingParseConversation>(objectId: draft.conversationID)
        author = Pointer<MessagingParseUser>(objectId: authorID)
        clientMessageId = draft.clientMessageID
        clientCreatedAt = draft.clientCreatedAt
        contentType = draft.content.kind
        text = draft.content.text
        linkURL = draft.content.linkURL?.absoluteString
        attachments = uploadedAttachments.isEmpty ? nil : uploadedAttachments
        let draftMetadata = draft.content.attributes
        metadata = draftMetadata.isEmpty ? nil : MessagingParseMetadata(draftMetadata)
        if let replyID = draft.replyToMessageID {
            replyTo = Pointer<MessagingParseMessage>(objectId: replyID)
        }
        deliveryType = draft.deliveryKind
        expressions = draft.expressions.isEmpty ? nil : draft.expressions
        isPinned = false
        isDeleted = false
    }

    func snapshot() throws -> MessagingMessageSnapshot {
        guard let objectID = objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "objectId")
        }
        guard let clientMessageID = clientMessageId else {
            throw MessagingModelError.missingField(className: Self.className, field: "clientMessageId")
        }
        guard let conversationID = conversation?.objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "conversation")
        }
        guard let authorID = author?.objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "author")
        }
        guard let clientCreatedAt = clientCreatedAt ?? createdAt else {
            throw MessagingModelError.missingField(className: Self.className, field: "clientCreatedAt")
        }
        guard let contentType = contentType else {
            throw MessagingModelError.missingField(className: Self.className, field: "contentType")
        }
        guard let deliveryType = deliveryType else {
            throw MessagingModelError.missingField(className: Self.className, field: "deliveryType")
        }

        let attachmentSnapshots = try (attachments ?? []).map { try $0.snapshot() }
        let content = MessagingMessageContent(
            kind: contentType,
            text: text,
            linkURL: linkURL.flatMap(URL.init(string:)),
            attachments: attachmentSnapshots,
            attributes: metadata?.values ?? [:]
        )
        return MessagingMessageSnapshot(
            objectID: objectID,
            clientMessageID: clientMessageID,
            conversationID: conversationID,
            authorID: authorID,
            clientCreatedAt: clientCreatedAt,
            serverCreatedAt: createdAt,
            serverUpdatedAt: updatedAt,
            content: content,
            replyToMessageID: replyTo?.objectId,
            replyCount: replyCount,
            latestReplyID: latestReply?.objectId,
            latestReplyAt: latestReplyAt,
            latestReplyAuthorID: latestReplyAuthor?.objectId,
            latestReplyText: latestReplyText,
            deliveryKind: deliveryType,
            editedAt: editedAt,
            isPinned: isPinned,
            pinnedAt: pinnedAt,
            pinnedByID: pinnedBy?.objectId,
            isDeleted: isDeleted,
            deletedAt: deletedAt,
            expressions: expressions ?? [],
            localState: .confirmed
        )
    }
}

public extension MessagingParseConversation {
    func snapshot() throws -> MessagingConversationSnapshot {
        guard let objectID = objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "objectId")
        }
        guard let creatorID = creator?.objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "creator")
        }
        guard let type = type else {
            throw MessagingModelError.missingField(className: Self.className, field: "type")
        }
        guard let activityAt = lastActivityAt ?? updatedAt ?? createdAt else {
            throw MessagingModelError.missingField(className: Self.className, field: "lastActivityAt")
        }
        return MessagingConversationSnapshot(
            id: objectID,
            createdAt: createdAt,
            clientConversationID: clientConversationId,
            contextKey: contextKey,
            kind: type,
            title: title,
            creatorID: creatorID,
            membershipRevision: membershipRevision ?? 0,
            latestMessageID: latestMessage?.objectId,
            latestMessageText: latestMessageText,
            lastActivityAt: activityAt,
            serverUpdatedAt: updatedAt,
            expressions: expressions ?? [],
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
    }
}

public extension MessagingParseConversationMember {
    func snapshot() throws -> MessagingMemberSnapshot {
        guard let objectID = objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "objectId")
        }
        guard let conversationID = conversation?.objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "conversation")
        }
        guard let userID = user?.objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "user")
        }
        guard let role = role else {
            throw MessagingModelError.missingField(className: Self.className, field: "role")
        }
        guard let joinedAt = joinedAt ?? createdAt else {
            throw MessagingModelError.missingField(className: Self.className, field: "joinedAt")
        }
        return MessagingMemberSnapshot(
            objectID: objectID,
            conversationID: conversationID,
            userID: userID,
            role: role,
            joinedAt: joinedAt,
            active: active,
            leftAt: leftAt,
            notificationsEnabled: notificationsEnabled ?? true,
            isHidden: isHidden ?? false,
            hiddenAt: hiddenAt,
            unreadCount: unreadCount ?? 0,
            lastReadMessageID: lastReadMessage?.objectId,
            lastReadAt: lastReadAt,
            typingExpiresAt: typingExpiresAt,
            serverUpdatedAt: updatedAt
        )
    }
}

public extension MessagingParseReaction {
    func snapshot() throws -> MessagingReactionSnapshot {
        guard let messageID = message?.objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "message")
        }
        guard let userID = user?.objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "user")
        }
        guard let type = type else {
            throw MessagingModelError.missingField(className: Self.className, field: "type")
        }
        guard let createdAt = createdAt else {
            throw MessagingModelError.missingField(className: Self.className, field: "createdAt")
        }
        return MessagingReactionSnapshot(
            objectID: objectId,
            messageID: messageID,
            userID: userID,
            type: type,
            createdAt: createdAt,
            serverUpdatedAt: updatedAt,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
    }
}

public extension MessagingParseReceipt {
    func snapshot() throws -> MessagingReceiptSnapshot {
        guard let messageID = message?.objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "message")
        }
        guard let userID = user?.objectId else {
            throw MessagingModelError.missingField(className: Self.className, field: "user")
        }

        guard let state = state else {
            throw MessagingModelError.missingField(className: Self.className, field: "state")
        }
        let occurredAt: Date
        switch state {
        case .read:
            guard let date = readAt else {
                throw MessagingModelError.missingField(className: Self.className, field: "readAt")
            }
            occurredAt = date
        case .delivered:
            guard let date = deliveredAt else {
                throw MessagingModelError.missingField(className: Self.className, field: "deliveredAt")
            }
            occurredAt = date
        case .sent:
            guard let date = messageCreatedAt ?? createdAt else {
                throw MessagingModelError.missingField(className: Self.className, field: "messageCreatedAt")
            }
            occurredAt = date
        }

        return MessagingReceiptSnapshot(
            objectID: objectId,
            messageID: messageID,
            userID: userID,
            state: state,
            occurredAt: occurredAt,
            serverUpdatedAt: updatedAt
        )
    }
}
