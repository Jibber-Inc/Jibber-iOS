//
//  ParseMessagingQueries.swift
//  MessagingPersistence
//

import Foundation
import MessagingContracts
import ParseSwift

public enum ParseMessagingQueryFactory {
    public static let maximumPageSize = 100

    public static func conversations(
        ids: [MessagingConversationID],
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> Query<MessagingParseConversation> {
        try validatePageSize(pageSize)
        if let cursor = cursor {
            try MessagingCursorCodec.validate(
                cursor,
                expectedScope: MessagingCursor.conversationScope
            )
        }
        var constraints: [QueryConstraint] = [
            containedIn(key: "objectId", array: ids),
            "isDeleted" == false
        ]
        if let cursor = cursor {
            let earlier = MessagingParseConversation.query("lastActivityAt" < cursor.sortDate)
            let tied = MessagingParseConversation.query(
                "lastActivityAt" == cursor.sortDate,
                "objectId" < cursor.stableID
            )
            constraints.append(or(queries: [earlier, tied]))
        }
        return MessagingParseConversation.query(constraints)
            .order([.descending("lastActivityAt"), .descending("objectId")])
            .limit(pageSize + 1)
    }

    /// Descending keyset pagination. The requested query returns one extra row
    /// so callers can derive `hasMore` without an additional count request.
    public static func messages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> Query<MessagingParseMessage> {
        try validatePageSize(pageSize)
        let scope = MessagingCursor.messageScope(conversationID: conversationID)
        if let cursor = cursor {
            try MessagingCursorCodec.validate(cursor, expectedScope: scope)
        }

        let conversation = Pointer<MessagingParseConversation>(objectId: conversationID)
        var constraints: [QueryConstraint] = [
            "conversation" == conversation,
            doesNotExist(key: "replyTo")
        ]
        if let cursor = cursor {
            let earlier = MessagingParseMessage.query("createdAt" < cursor.sortDate)
            let tied = MessagingParseMessage.query(
                "createdAt" == cursor.sortDate,
                "objectId" < cursor.stableID
            )
            constraints.append(or(queries: [earlier, tied]))
        }

        return MessagingParseMessage.query(constraints)
            .order([.descending("createdAt"), .descending("objectId")])
            .limit(pageSize + 1)
    }

    public static func replies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> Query<MessagingParseMessage> {
        try validatePageSize(pageSize)
        let scope = MessagingCursor.replyScope(messageID: messageID)
        if let cursor = cursor {
            try MessagingCursorCodec.validate(cursor, expectedScope: scope)
        }

        let message = Pointer<MessagingParseMessage>(objectId: messageID)
        var constraints: [QueryConstraint] = ["replyTo" == message]
        if let cursor = cursor {
            let earlier = MessagingParseMessage.query("createdAt" < cursor.sortDate)
            let tied = MessagingParseMessage.query(
                "createdAt" == cursor.sortDate,
                "objectId" < cursor.stableID
            )
            constraints.append(or(queries: [earlier, tied]))
        }

        return MessagingParseMessage.query(constraints)
            .order([.descending("createdAt"), .descending("objectId")])
            .limit(pageSize + 1)
    }

    /// Resolves every root's `latestReply` pointer with one object-id batch.
    /// The caller de-duplicates and bounds the ids to the root page size.
    public static func latestReplies(
        messageIDs: [MessagingMessageID]
    ) -> Query<MessagingParseMessage> {
        MessagingParseMessage.query(
            containedIn(key: "objectId", array: messageIDs)
        )
        .limit(min(messageIDs.count, maximumPageSize))
    }

    public static func pinnedMessages(
        conversationID: MessagingConversationID
    ) -> Query<MessagingParseMessage> {
        let conversation = Pointer<MessagingParseConversation>(objectId: conversationID)
        return MessagingParseMessage.query(
            "conversation" == conversation,
            "isPinned" == true,
            "isDeleted" != true
        )
        .order([.descending("pinnedAt"), .descending("objectId")])
        .limit(maximumPageSize)
    }

    /// Do not filter deleted messages from LiveQuery: soft-deletion must arrive
    /// as an update so every device can converge on the tombstone.
    public static func liveMessages(
        conversationID: MessagingConversationID
    ) -> Query<MessagingParseMessage> {
        let conversation = Pointer<MessagingParseConversation>(objectId: conversationID)
        return MessagingParseMessage.query("conversation" == conversation)
    }

    public static func activeMemberships(
        userID: MessagingUserID
    ) -> Query<MessagingParseConversationMember> {
        let user = Pointer<MessagingParseUser>(objectId: userID)
        return MessagingParseConversationMember.query(
            "user" == user,
            "active" == true,
            "isHidden" != true
        )
    }

    public static func members(
        conversationIDs: [MessagingConversationID]
    ) -> Query<MessagingParseConversationMember> {
        let conversations = conversationIDs.map {
            Pointer<MessagingParseConversation>(objectId: $0)
        }
        return MessagingParseConversationMember.query(
            containedIn(key: "conversation", array: conversations)
        )
    }

    public static func reactions(
        messageIDs: [MessagingMessageID]
    ) -> Query<MessagingParseReaction> {
        let messages = messageIDs.map { Pointer<MessagingParseMessage>(objectId: $0) }
        // Include soft-deleted rows so catch-up hydration can deliver the
        // versioned tombstone when this client missed its LiveQuery event.
        return MessagingParseReaction.query(
            containedIn(key: "message", array: messages)
        )
    }

    public static func receipts(
        messageIDs: [MessagingMessageID]
    ) -> Query<MessagingParseReceipt> {
        let messages = messageIDs.map { Pointer<MessagingParseMessage>(objectId: $0) }
        return MessagingParseReceipt.query(
            containedIn(key: "message", array: messages)
        )
    }

    public static func reactions(
        messageID: MessagingMessageID
    ) -> Query<MessagingParseReaction> {
        let message = Pointer<MessagingParseMessage>(objectId: messageID)
        return MessagingParseReaction.query("message" == message)
            .order(.ascending("createdAt"))
    }

    public static func receipts(
        messageID: MessagingMessageID
    ) -> Query<MessagingParseReceipt> {
        let message = Pointer<MessagingParseMessage>(objectId: messageID)
        return MessagingParseReceipt.query("message" == message)
            .order(.ascending("messageCreatedAt"), .ascending("createdAt"))
    }

    private static func validatePageSize(_ pageSize: Int) throws {
        guard (1...maximumPageSize).contains(pageSize) else {
            throw MessagingPaginationError.invalidPageSize(pageSize)
        }
    }
}

public enum ParseMessagingPageMapper {
    public static func messages(
        _ objects: [MessagingParseMessage],
        conversationID: MessagingConversationID,
        pageSize: Int
    ) throws -> MessagingPage<MessagingMessageSnapshot> {
        let snapshots = try objects.map { try $0.snapshot() }
        return try MessagingPageBuilder.messages(
            snapshots,
            conversationID: conversationID,
            pageSize: pageSize
        )
    }

    public static func conversations(
        _ objects: [MessagingParseConversation],
        pageSize: Int
    ) throws -> MessagingPage<MessagingConversationSnapshot> {
        let snapshots = try objects.map { try $0.snapshot() }
        return try MessagingPageBuilder.conversations(snapshots, pageSize: pageSize)
    }
}
