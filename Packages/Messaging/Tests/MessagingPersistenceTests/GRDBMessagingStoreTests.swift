import XCTest
import MessagingContracts
@testable import MessagingPersistence

final class GRDBMessagingStoreTests: XCTestCase {
    func testStageSendIsAtomicAndIdempotent() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let draft = makeDraft(clientMessageID: "client-idempotent-1")

        let first = try store.stageSend(draft: draft, authorID: "user-1")
        let second = try store.stageSend(draft: draft, authorID: "user-1")

        XCTAssertEqual(first.message, second.message)
        XCTAssertEqual(first.entry, second.entry)
        XCTAssertEqual(try store.readyOutboxEntries(at: Date(), limit: 10).count, 1)
        XCTAssertEqual(
            try store.cachedMessage(clientMessageID: draft.clientMessageID)?.localState,
            .queued
        )
    }

    func testOutboxPreservesPerConversationOrder() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let first = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "operation-1",
            conversationID: "conversation-1",
            mutation: .setPinned(
                conversationID: "conversation-1",
                messageID: "message-1",
                isPinned: true,
                changedAt: Date()
            )
        ))
        _ = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "operation-2",
            conversationID: "conversation-1",
            mutation: .setPinned(
                conversationID: "conversation-1",
                messageID: "message-2",
                isPinned: true,
                changedAt: Date()
            )
        ))

        XCTAssertEqual(
            try store.readyOutboxEntries(at: Date(), limit: 10).map(\.id),
            [first.id]
        )
        try store.removeOutboxEntry(id: first.id)
        XCTAssertEqual(
            try store.readyOutboxEntries(at: Date(), limit: 10).map(\.idempotencyKey),
            ["operation-2"]
        )
    }

    func testBlockedHeadIsQuarantinedWithoutDeadlockingConversation() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var blocked = try store.enqueue(makePinEntry(idempotencyKey: "blocked-1"))
        let later = try store.enqueue(makePinEntry(idempotencyKey: "later-1"))
        blocked.state = .blocked
        blocked.lastErrorDescription = "permission denied"
        try store.updateOutboxEntry(blocked)

        XCTAssertEqual(
            try store.readyOutboxEntries(at: Date(), limit: 10).map(\.id),
            [later.id]
        )
        XCTAssertEqual(
            try store.outboxEntry(idempotencyKey: blocked.idempotencyKey)?.state,
            .blocked
        )
    }

    func testExplicitRetryRestoresBlockedEntryAsFIFOBoundary() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try GRDBMessagingStore(inMemory: .init())
        var blocked = try store.enqueue(makePinEntry(idempotencyKey: "blocked-retry"))
        _ = try store.enqueue(makePinEntry(idempotencyKey: "later-retry"))
        blocked.state = .blocked
        blocked.attemptCount = 8
        blocked.lastErrorDescription = "terminal"
        try store.updateOutboxEntry(blocked)

        let retried = try store.retryBlockedOutboxEntry(
            idempotencyKey: blocked.idempotencyKey,
            at: now
        )

        XCTAssertEqual(retried.state, .queued)
        XCTAssertEqual(retried.attemptCount, 0)
        XCTAssertNil(retried.lastErrorDescription)
        XCTAssertEqual(
            try store.readyOutboxEntries(at: now, limit: 10).map(\.id),
            [blocked.id]
        )
    }

    func testExplicitCancelRemovesBlockedEntry() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var blocked = try store.enqueue(makePinEntry(idempotencyKey: "blocked-cancel"))
        blocked.state = .blocked
        try store.updateOutboxEntry(blocked)

        try store.cancelBlockedOutboxEntry(idempotencyKey: blocked.idempotencyKey)

        XCTAssertNil(try store.outboxEntry(idempotencyKey: blocked.idempotencyKey))
    }

    func testTypingPresenceCannotEnterDurableOutbox() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let entry = MessagingOutboxEntry(
            idempotencyKey: "typing-1",
            conversationID: "conversation-1",
            mutation: .setTyping(
                conversationID: "conversation-1",
                memberID: "member-1",
                expiresAt: Date().addingTimeInterval(12)
            )
        )

        XCTAssertThrowsError(try store.enqueue(entry)) { error in
            XCTAssertEqual(
                error as? MessagingPersistenceError,
                .ephemeralMutationCannotBeEnqueued
            )
        }
        XCTAssertTrue(try store.readyOutboxEntries(at: Date(), limit: 10).isEmpty)
    }

    func testConfirmationReplacesOptimisticCopyAndRemovesOutbox() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let draft = makeDraft(clientMessageID: "client-confirm-1")
        _ = try store.stageSend(draft: draft, authorID: "user-1")
        let confirmed = MessagingMessageSnapshot(
            objectID: "message-server-1",
            clientMessageID: draft.clientMessageID,
            conversationID: draft.conversationID,
            authorID: "user-1",
            clientCreatedAt: draft.clientCreatedAt,
            serverCreatedAt: Date(),
            serverUpdatedAt: Date(),
            content: draft.content,
            deliveryKind: draft.deliveryKind,
            localState: .confirmed
        )

        try store.confirm(message: confirmed, idempotencyKey: draft.clientMessageID)

        XCTAssertEqual(
            try store.cachedMessage(clientMessageID: draft.clientMessageID)?.objectID,
            "message-server-1"
        )
        XCTAssertNil(try store.outboxEntry(idempotencyKey: draft.clientMessageID))
    }

    func testInterruptedInFlightEntryRecoversAfterReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directory.appendingPathComponent("messaging.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let entryID: String
        do {
            let store = try GRDBMessagingStore(databaseURL: databaseURL)
            let staged = try store.stageSend(
                draft: makeDraft(clientMessageID: "client-recovery-1"),
                authorID: "user-1"
            )
            entryID = staged.entry.id
            var inFlight = staged.entry
            inFlight.state = .inFlight
            try store.updateOutboxEntry(inFlight)
        }

        let reopened = try GRDBMessagingStore(databaseURL: databaseURL)
        let recovered = try reopened.readyOutboxEntries(
            at: Date().addingTimeInterval(1),
            limit: 10
        )
        XCTAssertEqual(recovered.map(\.id), [entryID])
        XCTAssertEqual(recovered.first?.state, .retryScheduled)
    }

    func testTypingExpiryIsPersistedAndExpiresInContract() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let now = Date()
        let member = MessagingMemberSnapshot(
            objectID: "member-1",
            conversationID: "conversation-1",
            userID: "user-1",
            role: .member,
            joinedAt: now,
            typingExpiresAt: now.addingTimeInterval(10)
        )
        try store.upsert(members: [member])

        let cached = try XCTUnwrap(store.cachedMembers(conversationID: "conversation-1").first)
        XCTAssertTrue(cached.isTyping(at: now))
        XCTAssertFalse(cached.isTyping(at: now.addingTimeInterval(11)))
    }

    func testRootAndReplyCachesRemainSeparated() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let root = MessagingMessageSnapshot(
            objectID: "message-root",
            clientMessageID: "client-root",
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: Date(timeIntervalSince1970: 100),
            serverCreatedAt: Date(timeIntervalSince1970: 100),
            content: MessagingMessageContent(kind: .text, text: "Root"),
            deliveryKind: .conversational,
            localState: .confirmed
        )
        let reply = MessagingMessageSnapshot(
            objectID: "message-reply",
            clientMessageID: "client-reply",
            conversationID: "conversation-1",
            authorID: "user-2",
            clientCreatedAt: Date(timeIntervalSince1970: 101),
            serverCreatedAt: Date(timeIntervalSince1970: 101),
            content: MessagingMessageContent(kind: .text, text: "Reply"),
            replyToMessageID: root.objectID,
            deliveryKind: .conversational,
            localState: .confirmed
        )
        try store.upsert(messages: [root, reply])

        let roots = try store.cachedMessages(
            conversationID: root.conversationID,
            before: nil,
            pageSize: 10
        )
        let replies = try store.cachedReplies(
            messageID: try XCTUnwrap(root.objectID),
            before: nil,
            pageSize: 10
        )

        XCTAssertEqual(roots.items.map(\.objectID), [root.objectID])
        XCTAssertEqual(replies.items.map(\.objectID), [reply.objectID])
    }

    func testPinnedCacheIncludesRootMessagesAndReplies() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var root = makeMessage(
            objectID: "message-root-pinned",
            clientMessageID: "client-root-pinned"
        )
        root.isPinned = true
        var reply = makeMessage(
            objectID: "message-reply-pinned",
            clientMessageID: "client-reply-pinned",
            replyToMessageID: root.objectID
        )
        reply.isPinned = true
        let unpinned = makeMessage(
            objectID: "message-unpinned",
            clientMessageID: "client-unpinned"
        )
        try store.upsert(messages: [root, reply, unpinned])

        let pinned = try store.cachedPinnedMessages(conversationID: "conversation-1")

        XCTAssertEqual(
            Set(pinned.compactMap(\.objectID)),
            Set(["message-root-pinned", "message-reply-pinned"])
        )
    }

    func testRemoveConversationAtomicallyPurgesAggregateAndOutbox() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let draft = makeDraft(clientMessageID: "client-remove-1")
        let staged = try store.stageSend(draft: draft, authorID: "user-1")
        try store.upsert(conversations: [MessagingConversationSnapshot(
            id: draft.conversationID,
            kind: .direct,
            creatorID: "user-1",
            lastActivityAt: Date()
        )])
        try store.upsert(members: [MessagingMemberSnapshot(
            objectID: "member-remove-1",
            conversationID: draft.conversationID,
            userID: "user-1",
            role: .owner,
            joinedAt: Date()
        )])

        try store.removeConversation(id: draft.conversationID)

        XCTAssertNil(try store.cachedMessage(clientMessageID: draft.clientMessageID))
        XCTAssertTrue(try store.cachedMembers(conversationID: draft.conversationID).isEmpty)
        XCTAssertNil(try store.outboxEntry(idempotencyKey: staged.entry.idempotencyKey))
        XCTAssertTrue(try store.cachedConversations(before: nil, pageSize: 10).items.isEmpty)
    }

    private func makeDraft(clientMessageID: String) -> MessagingMessageDraft {
        MessagingMessageDraft(
            conversationID: "conversation-1",
            clientMessageID: clientMessageID,
            content: MessagingMessageContent(kind: .text, text: "Hello")
        )
    }

    private func makePinEntry(idempotencyKey: String) -> MessagingOutboxEntry {
        MessagingOutboxEntry(
            idempotencyKey: idempotencyKey,
            conversationID: "conversation-1",
            mutation: .setPinned(
                conversationID: "conversation-1",
                messageID: idempotencyKey,
                isPinned: true,
                changedAt: Date()
            )
        )
    }

    private func makeMessage(
        objectID: String,
        clientMessageID: String,
        replyToMessageID: String? = nil
    ) -> MessagingMessageSnapshot {
        MessagingMessageSnapshot(
            objectID: objectID,
            clientMessageID: clientMessageID,
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: Date(),
            serverCreatedAt: Date(),
            content: MessagingMessageContent(kind: .text, text: clientMessageID),
            replyToMessageID: replyToMessageID,
            deliveryKind: .conversational,
            localState: .confirmed
        )
    }
}
