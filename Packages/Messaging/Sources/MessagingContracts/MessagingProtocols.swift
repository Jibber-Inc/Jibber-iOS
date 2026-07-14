//
//  MessagingProtocols.swift
//  MessagingContracts
//

import Foundation

public struct MessagingAuthSession: Codable, Hashable, Sendable {
    public var userID: MessagingUserID
    public var sessionToken: String

    public init(userID: MessagingUserID, sessionToken: String) {
        self.userID = userID
        self.sessionToken = sessionToken
    }
}

/// Implement this in the application with the legacy PFUser while both SDKs
/// coexist. Keeping PFUser out of this target makes contracts extension-safe.
public protocol MessagingSessionProviding {
    func currentMessagingSession() throws -> MessagingAuthSession?
}

public protocol MessagingSessionActivating {
    @discardableResult
    func activateMessagingSession(_ session: MessagingAuthSession) async throws -> MessagingUserID
}

public enum MessagingMutation: Codable, Hashable, Sendable {
    case send(draft: MessagingMessageDraft, authorID: MessagingUserID)
    case setConversationTitle(
        conversationID: MessagingConversationID,
        title: String
    )
    case setConversationDeleted(
        conversationID: MessagingConversationID,
        isDeleted: Bool,
        changedAt: Date
    )
    case setMemberActive(
        conversationID: MessagingConversationID,
        userID: MessagingUserID,
        active: Bool
    )
    case setMemberHidden(
        conversationID: MessagingConversationID,
        memberID: String,
        isHidden: Bool
    )
    case edit(
        conversationID: MessagingConversationID,
        messageID: MessagingMessageID,
        text: String,
        editedAt: Date
    )
    case delete(
        conversationID: MessagingConversationID,
        messageID: MessagingMessageID,
        deletedAt: Date
    )
    case setPinned(
        conversationID: MessagingConversationID,
        messageID: MessagingMessageID,
        isPinned: Bool,
        changedAt: Date
    )
    case setReaction(
        conversationID: MessagingConversationID,
        messageID: MessagingMessageID,
        type: String,
        isSelected: Bool
    )
    case markRead(
        conversationID: MessagingConversationID,
        messageID: MessagingMessageID,
        messageCreatedAt: Date,
        readAt: Date
    )
    case markUnread(
        conversationID: MessagingConversationID,
        messageID: MessagingMessageID,
        changedAt: Date
    )
    case setTyping(
        conversationID: MessagingConversationID,
        memberID: String,
        expiresAt: Date?
    )
    case addMessageExpression(
        conversationID: MessagingConversationID,
        messageID: MessagingMessageID,
        reference: MessagingExpressionReference
    )
    case addConversationExpression(
        conversationID: MessagingConversationID,
        reference: MessagingExpressionReference
    )

    public var conversationID: MessagingConversationID {
        switch self {
        case .send(let draft, _): return draft.conversationID
        case .setConversationTitle(let conversationID, _),
             .setConversationDeleted(let conversationID, _, _),
             .setMemberActive(let conversationID, _, _),
             .setMemberHidden(let conversationID, _, _),
             .edit(let conversationID, _, _, _),
             .delete(let conversationID, _, _),
             .setPinned(let conversationID, _, _, _),
             .setReaction(let conversationID, _, _, _),
             .markRead(let conversationID, _, _, _),
             .markUnread(let conversationID, _, _),
             .setTyping(let conversationID, _, _),
             .addMessageExpression(let conversationID, _, _),
             .addConversationExpression(let conversationID, _):
            return conversationID
        }
    }
}

public enum MessagingMutationResult: Codable, Hashable, Sendable {
    case message(MessagingMessageSnapshot)
    case conversation(MessagingConversationSnapshot)
    case member(MessagingMemberSnapshot)
    case acknowledged
}

public protocol MessagingConversationRepository {
    func conversations(
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingConversationSnapshot>

    func conversation(id: MessagingConversationID) async throws -> MessagingConversationSnapshot
}

public protocol MessagingMessageRepository {
    func messages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot>

    func replies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot>

    func pinnedMessages(
        conversationID: MessagingConversationID
    ) async throws -> [MessagingMessageSnapshot]

    func perform(
        _ mutation: MessagingMutation,
        idempotencyKey: String
    ) async throws -> MessagingMutationResult
}

public protocol MessagingMembershipRepository {
    func members(
        conversationID: MessagingConversationID
    ) async throws -> [MessagingMemberSnapshot]

    func members(
        conversationIDs: [MessagingConversationID]
    ) async throws -> [MessagingMemberSnapshot]
}

public enum MessagingRealtimeEvent: Hashable, Sendable {
    case connected
    case disconnected(errorDescription: String?)
    /// The current user's membership set changed. Refresh the conversation
    /// list and replace the aggregate subscription with the new ID set.
    case conversationSetInvalidated(conversationID: MessagingConversationID)
    case conversationUpserted(MessagingConversationSnapshot)
    case memberUpserted(MessagingMemberSnapshot)
    case messageUpserted(MessagingMessageSnapshot)
    case messageDeleted(MessagingMessageSnapshot)
    case reactionUpserted(MessagingReactionSnapshot)
    case receiptUpserted(MessagingReceiptSnapshot)
}

public protocol MessagingRealtimeSubscription: AnyObject {
    func cancel()
}

public protocol MessagingRealtimeClient: AnyObject {
    func subscribe(
        conversationIDs: Set<MessagingConversationID>,
        eventHandler: @escaping (MessagingRealtimeEvent) -> Void
    ) throws -> MessagingRealtimeSubscription
}

public protocol MessagingCache: AnyObject {
    func upsert(conversations: [MessagingConversationSnapshot]) throws
    func cachedConversation(
        id: MessagingConversationID
    ) throws -> MessagingConversationSnapshot?
    func cachedConversations(
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> MessagingPage<MessagingConversationSnapshot>

    func upsert(messages: [MessagingMessageSnapshot]) throws
    func cachedMessages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> MessagingPage<MessagingMessageSnapshot>
    func cachedReplies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> MessagingPage<MessagingMessageSnapshot>
    /// Returns pinned roots and replies. This deliberately differs from
    /// `cachedMessages`, whose pagination surface contains root messages only.
    func cachedPinnedMessages(
        conversationID: MessagingConversationID
    ) throws -> [MessagingMessageSnapshot]
    func cachedMessage(clientMessageID: String) throws -> MessagingMessageSnapshot?
    func cachedMessage(objectID: MessagingMessageID) throws -> MessagingMessageSnapshot?

    func upsert(members: [MessagingMemberSnapshot]) throws
    func cachedMembers(conversationID: MessagingConversationID) throws -> [MessagingMemberSnapshot]
    /// Purges locally cached data after the server confirms that the current
    /// user no longer has access to a conversation.
    func removeConversation(id: MessagingConversationID) throws
    func removeAllMessagingData() throws
}

public enum MessagingOutboxState: String, Codable, CaseIterable, Hashable, Sendable {
    case queued
    case inFlight
    case retryScheduled
    case blocked
}

public struct MessagingOutboxEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var idempotencyKey: String
    public var conversationID: MessagingConversationID
    public var sequence: Int64
    public var mutation: MessagingMutation
    public var state: MessagingOutboxState
    public var attemptCount: Int
    public var createdAt: Date
    public var nextAttemptAt: Date
    public var lastErrorDescription: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        idempotencyKey: String,
        conversationID: MessagingConversationID,
        sequence: Int64 = 0,
        mutation: MessagingMutation,
        state: MessagingOutboxState = .queued,
        attemptCount: Int = 0,
        createdAt: Date = Date(),
        nextAttemptAt: Date? = nil,
        lastErrorDescription: String? = nil
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.conversationID = conversationID
        self.sequence = sequence
        self.mutation = mutation
        self.state = state
        self.attemptCount = attemptCount
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt ?? createdAt
        self.lastErrorDescription = lastErrorDescription
    }
}

public protocol MessagingOutbox: AnyObject {
    /// Atomically inserts the optimistic message and its outbox operation. If
    /// the same client message ID already exists, returns the existing values.
    func stageSend(
        draft: MessagingMessageDraft,
        authorID: MessagingUserID
    ) throws -> (message: MessagingMessageSnapshot, entry: MessagingOutboxEntry)

    func enqueue(_ entry: MessagingOutboxEntry) throws -> MessagingOutboxEntry
    func readyOutboxEntries(at date: Date, limit: Int) throws -> [MessagingOutboxEntry]
    func updateOutboxEntry(_ entry: MessagingOutboxEntry) throws
    func removeOutboxEntry(id: String) throws
    func outboxEntry(idempotencyKey: String) throws -> MessagingOutboxEntry?
    /// Requeues a permanently failed operation after an explicit user action.
    /// Retryable operations continue to be handled automatically by the worker.
    func retryBlockedOutboxEntry(
        idempotencyKey: String,
        at date: Date
    ) throws -> MessagingOutboxEntry
    /// Discards a permanently failed operation after an explicit user action.
    /// A failed optimistic send remains visible so the UI does not imply that
    /// it was delivered.
    func cancelBlockedOutboxEntry(idempotencyKey: String) throws
}

public protocol MessagingLocalStore: MessagingCache, MessagingOutbox {
    /// Replaces an optimistic message by client ID without changing its stable
    /// UI identity, then removes the corresponding outbox entry atomically.
    func confirm(
        message: MessagingMessageSnapshot,
        idempotencyKey: String
    ) throws
}

public protocol MessagingErrorClassifying {
    func isRetryableMessagingError(_ error: Error) -> Bool
}

public protocol MessagingClock {
    var now: Date { get }
}

public struct SystemMessagingClock: MessagingClock, Sendable {
    public init() {}
    public var now: Date { Date() }
}
