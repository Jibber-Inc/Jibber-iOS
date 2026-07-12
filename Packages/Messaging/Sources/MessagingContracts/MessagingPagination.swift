//
//  MessagingPagination.swift
//  MessagingContracts
//

import Foundation

/// Keyset cursor. The timestamp is the primary descending sort key and the
/// stable ID is the deterministic tie-breaker. `scope` prevents accidentally
/// applying a cursor from one conversation or resource to another.
public struct MessagingCursor: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var scope: String
    public var sortDate: Date
    public var stableID: String

    public init(
        version: Int = MessagingCursor.currentVersion,
        scope: String,
        sortDate: Date,
        stableID: String
    ) {
        self.version = version
        self.scope = scope
        self.sortDate = sortDate
        self.stableID = stableID
    }

    public static func messages(
        conversationID: MessagingConversationID,
        sortDate: Date,
        stableID: String
    ) -> MessagingCursor {
        MessagingCursor(
            scope: messageScope(conversationID: conversationID),
            sortDate: sortDate,
            stableID: stableID
        )
    }

    public static func conversations(sortDate: Date, stableID: String) -> MessagingCursor {
        MessagingCursor(scope: conversationScope, sortDate: sortDate, stableID: stableID)
    }

    public static func replies(
        messageID: MessagingMessageID,
        sortDate: Date,
        stableID: String
    ) -> MessagingCursor {
        MessagingCursor(
            scope: replyScope(messageID: messageID),
            sortDate: sortDate,
            stableID: stableID
        )
    }

    public static func messageScope(conversationID: MessagingConversationID) -> String {
        "messages:\(conversationID)"
    }

    public static func replyScope(messageID: MessagingMessageID) -> String {
        "replies:\(messageID)"
    }

    public static let conversationScope = "conversations"
}

public struct MessagingPage<Element: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var items: [Element]
    public var nextCursor: MessagingCursor?
    public var hasMore: Bool

    public init(items: [Element], nextCursor: MessagingCursor?, hasMore: Bool) {
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public enum MessagingPaginationError: Error, Equatable, Sendable {
    case invalidPageSize(Int)
    case unsupportedCursorVersion(Int)
    case cursorScopeMismatch(expected: String, actual: String)
    case invalidEncodedCursor
}

public enum MessagingCursorCodec {
    public static func encode(_ cursor: MessagingCursor) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(cursor)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ value: String) throws -> MessagingCursor {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            throw MessagingPaginationError.invalidEncodedCursor
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let cursor = try? decoder.decode(MessagingCursor.self, from: data) else {
            throw MessagingPaginationError.invalidEncodedCursor
        }
        try validate(cursor)
        return cursor
    }

    public static func validate(_ cursor: MessagingCursor, expectedScope: String? = nil) throws {
        guard cursor.version == MessagingCursor.currentVersion else {
            throw MessagingPaginationError.unsupportedCursorVersion(cursor.version)
        }
        if let expectedScope = expectedScope, cursor.scope != expectedScope {
            throw MessagingPaginationError.cursorScopeMismatch(
                expected: expectedScope,
                actual: cursor.scope
            )
        }
    }
}

public enum MessagingPageBuilder {
    /// Builds a page from `pageSize + 1` descending message candidates.
    public static func messages(
        _ candidates: [MessagingMessageSnapshot],
        conversationID: MessagingConversationID,
        pageSize: Int
    ) throws -> MessagingPage<MessagingMessageSnapshot> {
        guard pageSize > 0 else {
            throw MessagingPaginationError.invalidPageSize(pageSize)
        }
        let hasMore = candidates.count > pageSize
        let items = Array(candidates.prefix(pageSize))
        let cursor = hasMore ? items.last.map {
            MessagingCursor.messages(
                conversationID: conversationID,
                sortDate: $0.sortDate,
                stableID: $0.objectID ?? $0.stableID
            )
        } : nil
        return MessagingPage(items: items, nextCursor: cursor, hasMore: hasMore)
    }

    public static func replies(
        _ candidates: [MessagingMessageSnapshot],
        messageID: MessagingMessageID,
        pageSize: Int
    ) throws -> MessagingPage<MessagingMessageSnapshot> {
        guard pageSize > 0 else {
            throw MessagingPaginationError.invalidPageSize(pageSize)
        }
        let hasMore = candidates.count > pageSize
        let items = Array(candidates.prefix(pageSize))
        let cursor = hasMore ? items.last.map {
            MessagingCursor.replies(
                messageID: messageID,
                sortDate: $0.sortDate,
                stableID: $0.objectID ?? $0.stableID
            )
        } : nil
        return MessagingPage(items: items, nextCursor: cursor, hasMore: hasMore)
    }

    /// Builds a page from `pageSize + 1` descending conversation candidates.
    public static func conversations(
        _ candidates: [MessagingConversationSnapshot],
        pageSize: Int
    ) throws -> MessagingPage<MessagingConversationSnapshot> {
        guard pageSize > 0 else {
            throw MessagingPaginationError.invalidPageSize(pageSize)
        }
        let hasMore = candidates.count > pageSize
        let items = Array(candidates.prefix(pageSize))
        let cursor = hasMore ? items.last.map {
            MessagingCursor.conversations(sortDate: $0.lastActivityAt, stableID: $0.id)
        } : nil
        return MessagingPage(items: items, nextCursor: cursor, hasMore: hasMore)
    }
}
