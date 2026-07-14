import XCTest
import MessagingContracts
@testable import MessagingPersistence

final class GRDBMessagingStoreTests: XCTestCase {
    func testCachedConversationReadsOnlyRequestedConversation() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let first = MessagingConversationSnapshot(
            id: "conversation-1",
            kind: .direct,
            title: "First",
            creatorID: "user-1",
            lastActivityAt: Date(timeIntervalSince1970: 100)
        )
        let second = MessagingConversationSnapshot(
            id: "conversation-2",
            kind: .direct,
            title: "Second",
            creatorID: "user-1",
            lastActivityAt: Date(timeIntervalSince1970: 200)
        )
        try store.upsert(conversations: [first, second])

        XCTAssertEqual(try store.cachedConversation(id: first.id), first)
        XCTAssertNil(try store.cachedConversation(id: "missing"))
    }

    func testConversationUpsertUsesServerFreshness() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let current = MessagingConversationSnapshot(
            id: "conversation-freshness",
            kind: .group,
            title: "Current",
            creatorID: "user-1",
            membershipRevision: 3,
            latestMessageID: "message-current",
            lastActivityAt: Date(timeIntervalSince1970: 300),
            serverUpdatedAt: Date(timeIntervalSince1970: 300),
            isDeleted: true,
            deletedAt: Date(timeIntervalSince1970: 299)
        )
        try store.upsert(conversations: [current])

        var stale = current
        stale.title = "Stale"
        stale.membershipRevision = 1
        stale.latestMessageID = "message-stale"
        stale.serverUpdatedAt = Date(timeIntervalSince1970: 200)
        stale.isDeleted = false
        stale.deletedAt = nil
        try store.upsert(conversations: [stale])

        XCTAssertEqual(try store.cachedConversation(id: current.id), current)

        var equalVersion = stale
        equalVersion.serverUpdatedAt = current.serverUpdatedAt
        try store.upsert(conversations: [equalVersion])
        XCTAssertEqual(try store.cachedConversation(id: current.id), current)

        var newer = current
        newer.title = "Newer"
        newer.membershipRevision = 4
        newer.serverUpdatedAt = Date(timeIntervalSince1970: 400)
        newer.isDeleted = false
        newer.deletedAt = nil
        try store.upsert(conversations: [newer])
        XCTAssertEqual(try store.cachedConversation(id: current.id), newer)
    }

    func testMemberUpsertUsesServerFreshnessForUnreadTypingAndActiveState() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let current = MessagingMemberSnapshot(
            objectID: "member-freshness",
            conversationID: "conversation-freshness",
            userID: "user-1",
            role: .member,
            joinedAt: Date(timeIntervalSince1970: 100),
            active: false,
            leftAt: Date(timeIntervalSince1970: 290),
            unreadCount: 0,
            typingExpiresAt: nil,
            serverUpdatedAt: Date(timeIntervalSince1970: 300)
        )
        try store.upsert(members: [current])

        var stale = current
        stale.active = true
        stale.leftAt = nil
        stale.unreadCount = 12
        stale.typingExpiresAt = Date(timeIntervalSince1970: 500)
        stale.serverUpdatedAt = Date(timeIntervalSince1970: 200)
        try store.upsert(members: [stale])

        XCTAssertEqual(
            try store.cachedMembers(conversationID: current.conversationID),
            [current]
        )

        var newer = stale
        newer.unreadCount = 2
        newer.typingExpiresAt = Date(timeIntervalSince1970: 600)
        newer.serverUpdatedAt = Date(timeIntervalSince1970: 400)
        try store.upsert(members: [newer])
        XCTAssertEqual(
            try store.cachedMembers(conversationID: current.conversationID),
            [newer]
        )
    }

    func testMemberFreshnessPreservesLegacyNilTimestampCompatibility() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var legacy = MessagingMemberSnapshot(
            objectID: "member-legacy-freshness",
            conversationID: "conversation-legacy-freshness",
            userID: "user-1",
            role: .member,
            joinedAt: Date(timeIntervalSince1970: 100),
            unreadCount: 4
        )
        try store.upsert(members: [legacy])

        legacy.unreadCount = 3
        try store.upsert(members: [legacy])
        XCTAssertEqual(
            try store.cachedMembers(conversationID: legacy.conversationID).first?.unreadCount,
            3
        )

        var timestamped = legacy
        timestamped.unreadCount = 0
        timestamped.serverUpdatedAt = Date(timeIntervalSince1970: 300)
        try store.upsert(members: [timestamped])

        legacy.unreadCount = 9
        try store.upsert(members: [legacy])
        XCTAssertEqual(
            try store.cachedMembers(conversationID: legacy.conversationID),
            [timestamped]
        )
    }

    func testCachedConversationStateReturnsConsistentAggregate() async throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let conversation = MessagingConversationSnapshot(
            id: "conversation-aggregate",
            kind: .direct,
            creatorID: "user-1",
            lastActivityAt: Date(timeIntervalSince1970: 100)
        )
        let member = MessagingMemberSnapshot(
            objectID: "member-aggregate",
            conversationID: conversation.id,
            userID: "user-1",
            role: .owner,
            joinedAt: Date(timeIntervalSince1970: 90)
        )
        var message = makeMessage(
            objectID: "message-aggregate",
            clientMessageID: "client-aggregate"
        )
        message.conversationID = conversation.id
        message.clientCreatedAt = Date(timeIntervalSince1970: 80)
        message.serverCreatedAt = Date(timeIntervalSince1970: 80)
        message.isPinned = true
        try store.upsert(conversations: [conversation])
        try store.upsert(members: [member])
        try store.upsert(messages: [message])

        let state = try await store.cachedConversationState(
            conversationID: conversation.id,
            pageSize: 10
        )

        XCTAssertEqual(state.conversation, conversation)
        XCTAssertEqual(state.members, [member])
        XCTAssertEqual(state.messages.items, [message])
        XCTAssertEqual(state.pinnedMessages, [message])
    }

    func testLocalCacheCanReadMoreThanOneRemotePage() throws {
        let store = try GRDBMessagingStore(inMemory: .init(messagesPerConversation: 250))
        let messages = (0..<125).map { index in
            var message = self.makeMessage(
                objectID: "message-\(index)",
                clientMessageID: "client-\(index)"
            )
            message.conversationID = "conversation"
            message.clientCreatedAt = Date(timeIntervalSince1970: TimeInterval(index))
            message.serverCreatedAt = message.clientCreatedAt
            return message
        }
        try store.upsert(messages: messages)

        let page = try store.cachedMessages(
            conversationID: "conversation",
            before: nil,
            pageSize: 125
        )

        XCTAssertEqual(page.items.count, 125)
        XCTAssertFalse(page.hasMore)
    }

    func testPruningRetainsOnlyBoundedNewestPinnedOverflow() throws {
        let store = try GRDBMessagingStore(inMemory: .init(messagesPerConversation: 2))
        let messages = (0..<7).map { index in
            var message = self.makeMessage(
                objectID: "message-retention-\(index)",
                clientMessageID: "client-retention-\(index)"
            )
            message.clientCreatedAt = Date(timeIntervalSince1970: TimeInterval(index))
            message.serverCreatedAt = message.clientCreatedAt
            message.isPinned = index <= 2
            return message
        }

        try store.upsert(messages: messages)

        let retained = try store.cachedMessages(
            ids: messages.map { $0.objectID ?? $0.stableID }
        )
        XCTAssertEqual(
            Set(retained.map(\.stableID)),
            Set([
                messages[6].stableID,
                messages[5].stableID,
                messages[2].stableID,
                messages[1].stableID
            ])
        )
        XCTAssertEqual(
            try store.cachedPinnedMessages(conversationID: "conversation-1")
                .map(\.stableID),
            [messages[2].stableID, messages[1].stableID]
        )
    }

    func testPruningRetainsRootForRetainedReplyWithoutUnboundedOrphans() throws {
        let store = try GRDBMessagingStore(inMemory: .init(messagesPerConversation: 2))
        var root = makeMessage(
            objectID: "message-retained-root",
            clientMessageID: "client-retained-root"
        )
        root.clientCreatedAt = Date(timeIntervalSince1970: 0)
        root.serverCreatedAt = root.clientCreatedAt
        var oldOrdinary = makeMessage(
            objectID: "message-old-ordinary",
            clientMessageID: "client-old-ordinary"
        )
        oldOrdinary.clientCreatedAt = Date(timeIntervalSince1970: 1)
        oldOrdinary.serverCreatedAt = oldOrdinary.clientCreatedAt
        var reply = makeMessage(
            objectID: "message-retained-reply",
            clientMessageID: "client-retained-reply",
            replyToMessageID: root.objectID
        )
        reply.clientCreatedAt = Date(timeIntervalSince1970: 3)
        reply.serverCreatedAt = reply.clientCreatedAt
        var newest = makeMessage(
            objectID: "message-newest-root",
            clientMessageID: "client-newest-root"
        )
        newest.clientCreatedAt = Date(timeIntervalSince1970: 4)
        newest.serverCreatedAt = newest.clientCreatedAt

        try store.upsert(messages: [root, oldOrdinary, reply, newest])

        XCTAssertNotNil(try store.cachedMessage(objectID: root.objectID!))
        XCTAssertNotNil(try store.cachedMessage(objectID: reply.objectID!))
        XCTAssertNil(try store.cachedMessage(objectID: oldOrdinary.objectID!))

        let laterMessages = (5...6).map { index in
            var message = self.makeMessage(
                objectID: "message-later-\(index)",
                clientMessageID: "client-later-\(index)"
            )
            message.clientCreatedAt = Date(timeIntervalSince1970: TimeInterval(index))
            message.serverCreatedAt = message.clientCreatedAt
            return message
        }
        try store.upsert(messages: laterMessages)

        XCTAssertNil(try store.cachedMessage(objectID: root.objectID!))
        XCTAssertNil(try store.cachedMessage(objectID: reply.objectID!))
        XCTAssertEqual(
            try store.cachedMessages(
                ids: laterMessages.map { $0.objectID ?? $0.stableID }
            ).count,
            2
        )
    }

    func testCachedMessagesByIDsResolvesBothIdentitiesInRequestedOrder() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let first = makeMessage(
            objectID: "message-batch-first",
            clientMessageID: "client-batch-first"
        )
        let second = makeMessage(
            objectID: "message-batch-second",
            clientMessageID: "client-batch-second"
        )
        try store.upsert(messages: [first, second])

        let values = try store.cachedMessages(ids: [
            "message-batch-second",
            "client-batch-first",
            "missing",
            "client-batch-second"
        ])

        XCTAssertEqual(
            values.map(\.stableID),
            [second.stableID, first.stableID, second.stableID]
        )
    }

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

    func testReactionEnqueueAtomicallyPersistsOptimisticSelection() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let message = makeMessage(
            objectID: "message-reaction-select",
            clientMessageID: "client-reaction-select"
        )
        try store.upsert(messages: [message])
        let entry = MessagingOutboxEntry(
            idempotencyKey: "reaction-select-1",
            conversationID: message.conversationID,
            mutation: .setReaction(
                conversationID: message.conversationID,
                messageID: try XCTUnwrap(message.objectID),
                type: MessagingReactionType.like,
                isSelected: true
            ),
            actorID: "current-user",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let first = try store.enqueue(entry)
        let duplicate = try store.enqueue(entry)
        let cached = try XCTUnwrap(store.cachedMessage(objectID: "message-reaction-select"))
        let reaction = try XCTUnwrap(cached.reactions.first)

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(reaction.userID, "current-user")
        XCTAssertEqual(reaction.reactionType, .like)
        XCTAssertTrue(reaction.isActive)
        XCTAssertEqual(reaction.localMutationID, entry.idempotencyKey)
        XCTAssertEqual(reaction.localMutationState, .selecting)
        XCTAssertTrue(cached.reactionGroups(currentUserID: "current-user")[0].isSelectedByCurrentUser)
        XCTAssertEqual(try store.readyOutboxEntries(at: Date(), limit: 10).count, 1)
    }

    func testOptimisticReactionRemovalAndOutboxSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directory.appendingPathComponent("messaging.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let store = try GRDBMessagingStore(databaseURL: databaseURL)
            var message = makeMessage(
                objectID: "message-reaction-remove",
                clientMessageID: "client-reaction-remove"
            )
            message.reactions = [MessagingReactionSnapshot(
                objectID: "reaction-remove",
                messageID: "message-reaction-remove",
                userID: "current-user",
                type: MessagingReactionType.love.rawValue,
                createdAt: Date(timeIntervalSince1970: 100),
                serverUpdatedAt: Date(timeIntervalSince1970: 150)
            )]
            try store.upsert(messages: [message])
            _ = try store.enqueue(MessagingOutboxEntry(
                idempotencyKey: "reaction-remove-1",
                conversationID: message.conversationID,
                mutation: .setReaction(
                    conversationID: message.conversationID,
                    messageID: "message-reaction-remove",
                    type: MessagingReactionType.love,
                    isSelected: false
                ),
                actorID: "current-user",
                createdAt: Date(timeIntervalSince1970: 200)
            ))
        }

        let reopened = try GRDBMessagingStore(databaseURL: databaseURL)
        let cached = try XCTUnwrap(
            reopened.cachedMessage(objectID: "message-reaction-remove")
        )
        let reaction = try XCTUnwrap(cached.reactions.first)
        XCTAssertFalse(reaction.isActive)
        XCTAssertEqual(reaction.localMutationState, .removing)
        XCTAssertEqual(reaction.deletedAt, Date(timeIntervalSince1970: 200))
        XCTAssertNil(cached.selectedReactionType(for: "current-user"))
        XCTAssertEqual(
            try reopened.outboxEntry(idempotencyKey: "reaction-remove-1")?.actorID,
            "current-user"
        )
    }

    func testBlockedReactionIsMarkedFailedAndExplicitRetryRestoresPendingState() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let message = makeMessage(
            objectID: "message-reaction-failure",
            clientMessageID: "client-reaction-failure"
        )
        try store.upsert(messages: [message])
        var entry = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "reaction-failure-1",
            conversationID: message.conversationID,
            mutation: .setReaction(
                conversationID: message.conversationID,
                messageID: "message-reaction-failure",
                type: MessagingReactionType.dislike,
                isSelected: true
            ),
            actorID: "current-user"
        ))
        entry.state = .blocked
        entry.lastErrorDescription = "permission denied"
        try store.updateOutboxEntry(entry)

        var reaction = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-failure")?.reactions.first
        )
        XCTAssertEqual(reaction.localMutationState, .selectionFailed)
        XCTAssertEqual(reaction.lastFailureDescription, "permission denied")

        _ = try store.retryBlockedOutboxEntry(
            idempotencyKey: entry.idempotencyKey,
            at: Date(timeIntervalSince1970: 300)
        )

        reaction = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-failure")?.reactions.first
        )
        XCTAssertEqual(reaction.localMutationState, .selecting)
        XCTAssertNil(reaction.lastFailureDescription)
    }

    func testBlockedReactionRemovalRollsBackVisibleAndRetryRestoresTombstone() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var message = makeMessage(
            objectID: "message-reaction-removal-failure",
            clientMessageID: "client-reaction-removal-failure"
        )
        message.reactions = [MessagingReactionSnapshot(
            objectID: "reaction-removal-failure",
            messageID: "message-reaction-removal-failure",
            userID: "current-user",
            type: MessagingReactionType.like.rawValue,
            createdAt: Date(timeIntervalSince1970: 100)
        )]
        try store.upsert(messages: [message])
        var entry = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "reaction-removal-failure-1",
            conversationID: message.conversationID,
            mutation: .setReaction(
                conversationID: message.conversationID,
                messageID: "message-reaction-removal-failure",
                type: .like,
                isSelected: false
            ),
            actorID: "current-user"
        ))
        entry.state = .blocked
        entry.lastErrorDescription = "offline terminal"
        try store.updateOutboxEntry(entry)

        var reaction = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-removal-failure")?.reactions.first
        )
        XCTAssertTrue(reaction.isActive)
        XCTAssertEqual(reaction.localMutationState, .removalFailed)

        _ = try store.retryBlockedOutboxEntry(
            idempotencyKey: entry.idempotencyKey,
            at: Date(timeIntervalSince1970: 300)
        )

        reaction = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-removal-failure")?.reactions.first
        )
        XCTAssertFalse(reaction.isActive)
        XCTAssertEqual(reaction.localMutationState, .removing)
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

    func testExplicitSendRetryRestoresOptimisticMessageState() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let draft = makeDraft(clientMessageID: "blocked-send-retry")
        var staged = try store.stageSend(draft: draft, authorID: "user-1")
        staged.entry.state = .blocked
        staged.entry.attemptCount = 8
        staged.entry.lastErrorDescription = "terminal"
        var failedMessage = staged.message
        failedMessage.localState = .failed
        failedMessage.lastFailureDescription = "terminal"
        try store.upsert(messages: [failedMessage])
        try store.updateOutboxEntry(staged.entry)

        _ = try store.retryBlockedOutboxEntry(
            idempotencyKey: draft.clientMessageID,
            at: Date()
        )

        let recovered = try XCTUnwrap(
            store.cachedMessage(clientMessageID: draft.clientMessageID)
        )
        XCTAssertEqual(recovered.localState, .queued)
        XCTAssertNil(recovered.lastFailureDescription)
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

    func testAtomicUpsertRejectsStaleCoreReceiptAndReactionSnapshots() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var newest = makeMessage(
            objectID: "message-race-stale",
            clientMessageID: "client-race-stale"
        )
        newest.serverUpdatedAt = Date(timeIntervalSince1970: 300)
        newest.content.text = "Newest core"
        newest.receipts = [MessagingReceiptSnapshot(
            objectID: "receipt-race-stale",
            messageID: "message-race-stale",
            userID: "user-2",
            state: .read,
            occurredAt: Date(timeIntervalSince1970: 290),
            serverUpdatedAt: Date(timeIntervalSince1970: 300)
        )]
        newest.reactions = [MessagingReactionSnapshot(
            objectID: "reaction-race-stale",
            messageID: "message-race-stale",
            userID: "user-2",
            type: "heart",
            createdAt: Date(timeIntervalSince1970: 100),
            serverUpdatedAt: Date(timeIntervalSince1970: 300),
            isDeleted: true,
            deletedAt: Date(timeIntervalSince1970: 299)
        )]
        try store.upsert(messages: [newest])

        var stalePage = newest
        stalePage.serverUpdatedAt = Date(timeIntervalSince1970: 200)
        stalePage.content.text = "Stale core"
        stalePage.receipts = [MessagingReceiptSnapshot(
            objectID: "receipt-race-stale",
            messageID: "message-race-stale",
            userID: "user-2",
            state: .delivered,
            occurredAt: Date(timeIntervalSince1970: 190),
            serverUpdatedAt: Date(timeIntervalSince1970: 200)
        )]
        stalePage.reactions = [MessagingReactionSnapshot(
            objectID: "reaction-race-stale",
            messageID: "message-race-stale",
            userID: "user-2",
            type: "heart",
            createdAt: Date(timeIntervalSince1970: 100),
            serverUpdatedAt: Date(timeIntervalSince1970: 200)
        )]
        try store.upsert(messages: [stalePage])

        let cached = try XCTUnwrap(store.cachedMessage(objectID: "message-race-stale"))
        XCTAssertEqual(cached.content.text, "Newest core")
        XCTAssertEqual(cached.serverUpdatedAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(cached.receipts.first?.state, .read)
        XCTAssertEqual(cached.receipts.first?.serverUpdatedAt, Date(timeIntervalSince1970: 300))
        XCTAssertTrue(try XCTUnwrap(cached.reactions.first).isDeleted)
        XCTAssertEqual(cached.reactions.first?.serverUpdatedAt, Date(timeIntervalSince1970: 300))
    }

    func testAtomicUpsertAcceptsNewerReceiptReversalAndReactionDeletion() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var original = makeMessage(
            objectID: "message-race-newer",
            clientMessageID: "client-race-newer"
        )
        original.serverUpdatedAt = Date(timeIntervalSince1970: 100)
        original.receipts = [MessagingReceiptSnapshot(
            objectID: "receipt-race-newer",
            messageID: "message-race-newer",
            userID: "user-2",
            state: .read,
            occurredAt: Date(timeIntervalSince1970: 190),
            serverUpdatedAt: Date(timeIntervalSince1970: 200)
        )]
        original.reactions = [MessagingReactionSnapshot(
            objectID: "reaction-race-newer",
            messageID: "message-race-newer",
            userID: "user-2",
            type: "heart",
            createdAt: Date(timeIntervalSince1970: 100),
            serverUpdatedAt: Date(timeIntervalSince1970: 200)
        )]
        try store.upsert(messages: [original])

        var newerRelatedState = original
        newerRelatedState.receipts = [MessagingReceiptSnapshot(
            objectID: "receipt-race-newer",
            messageID: "message-race-newer",
            userID: "user-2",
            state: .delivered,
            occurredAt: Date(timeIntervalSince1970: 150),
            serverUpdatedAt: Date(timeIntervalSince1970: 300)
        )]
        newerRelatedState.reactions = [MessagingReactionSnapshot(
            objectID: "reaction-race-newer",
            messageID: "message-race-newer",
            userID: "user-2",
            type: "heart",
            createdAt: Date(timeIntervalSince1970: 100),
            serverUpdatedAt: Date(timeIntervalSince1970: 300),
            isDeleted: true,
            deletedAt: Date(timeIntervalSince1970: 299)
        )]
        try store.upsert(messages: [newerRelatedState])

        let cached = try XCTUnwrap(store.cachedMessage(objectID: "message-race-newer"))
        XCTAssertEqual(cached.receipts.first?.state, .delivered)
        XCTAssertEqual(cached.receipts.first?.serverUpdatedAt, Date(timeIntervalSince1970: 300))
        XCTAssertTrue(try XCTUnwrap(cached.reactions.first).isDeleted)
        XCTAssertEqual(cached.reactions.first?.serverUpdatedAt, Date(timeIntervalSince1970: 300))
    }

    func testDelayedConfirmationPreservesNewerCoreAndFinishesOptimisticSend() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let draft = makeDraft(clientMessageID: "client-confirm-race")
        _ = try store.stageSend(draft: draft, authorID: "user-1")

        let newerLocal = MessagingMessageSnapshot(
            objectID: "message-confirm-race",
            clientMessageID: draft.clientMessageID,
            conversationID: draft.conversationID,
            authorID: "user-1",
            clientCreatedAt: draft.clientCreatedAt,
            serverCreatedAt: Date(timeIntervalSince1970: 100),
            serverUpdatedAt: Date(timeIntervalSince1970: 300),
            content: MessagingMessageContent(kind: .text, text: "Newer edit"),
            deliveryKind: draft.deliveryKind,
            localState: .sending,
            lastFailureDescription: "in flight"
        )
        try store.upsert(messages: [newerLocal])

        var delayedConfirmation = newerLocal
        delayedConfirmation.serverUpdatedAt = Date(timeIntervalSince1970: 200)
        delayedConfirmation.content.text = "Original send"
        delayedConfirmation.localState = .confirmed
        delayedConfirmation.lastFailureDescription = nil
        try store.confirm(
            message: delayedConfirmation,
            idempotencyKey: draft.clientMessageID
        )

        let cached = try XCTUnwrap(
            store.cachedMessage(clientMessageID: draft.clientMessageID)
        )
        XCTAssertEqual(cached.content.text, "Newer edit")
        XCTAssertEqual(cached.serverUpdatedAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(cached.localState, .confirmed)
        XCTAssertNil(cached.lastFailureDescription)
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

    func testLatestReplyPreviewPreservesRichContentAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directory.appendingPathComponent("messaging.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        var root = makeMessage(
            objectID: "message-preview-root",
            clientMessageID: "client-preview-root"
        )
        root.replyCount = 1
        root.latestReplyID = "message-preview-reply"
        root.latestReplyAt = Date(timeIntervalSince1970: 200)
        root.latestReplyAuthorID = "maya"
        root.latestReplyText = "Generated this for you"

        var reply = makeMessage(
            objectID: "message-preview-reply",
            clientMessageID: "client-preview-reply",
            replyToMessageID: root.objectID
        )
        reply.authorID = "maya"
        reply.content = MessagingMessageContent(
            kind: .media,
            text: "Generated this for you",
            linkURL: URL(string: "https://example.com/source"),
            attachments: [MessagingAttachmentSnapshot(
                id: "maya-image",
                kind: .image,
                remoteURL: URL(string: "https://example.com/maya-image.png"),
                thumbnailURL: URL(string: "https://example.com/maya-thumb.png"),
                mimeType: "image/png",
                pixelWidth: 1024,
                pixelHeight: 1024
            )]
        )

        do {
            let store = try GRDBMessagingStore(databaseURL: databaseURL)
            try store.upsert(messages: [root, reply])
        }

        let reopened = try GRDBMessagingStore(databaseURL: databaseURL)
        let cachedRoot = try XCTUnwrap(
            reopened.cachedMessage(objectID: "message-preview-root")
        )
        let cachedReply = try XCTUnwrap(
            reopened.cachedMessage(objectID: "message-preview-reply")
        )
        let preview = try XCTUnwrap(
            MessagingReplyPreviewResolver.replies(
                for: cachedRoot,
                from: [cachedReply]
            ).first
        )

        XCTAssertEqual(cachedRoot.latestReplyID, reply.objectID)
        XCTAssertEqual(cachedRoot.latestReplyAuthorID, "maya")
        XCTAssertEqual(preview.content, reply.content)
    }

    func testReplyPreviewReadCombinesExactPointerWithCrossControllerOptimisticReply() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var authoritative = makeMessage(
            objectID: "reply-authoritative",
            clientMessageID: "client-reply-authoritative",
            replyToMessageID: "root-1"
        )
        authoritative.clientCreatedAt = Date(timeIntervalSince1970: 100)
        authoritative.serverCreatedAt = authoritative.clientCreatedAt
        var staleConfirmed = makeMessage(
            objectID: "reply-stale-confirmed",
            clientMessageID: "client-reply-stale-confirmed",
            replyToMessageID: "root-1"
        )
        staleConfirmed.clientCreatedAt = Date(timeIntervalSince1970: 200)
        staleConfirmed.serverCreatedAt = staleConfirmed.clientCreatedAt
        let optimistic = MessagingMessageSnapshot(
            clientMessageID: "client-reply-optimistic",
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: Date(timeIntervalSince1970: 300),
            content: MessagingMessageContent(kind: .text, text: "Optimistic"),
            replyToMessageID: "root-1",
            deliveryKind: .conversational,
            localState: .queued
        )
        let foreignReply = makeMessage(
            objectID: "reply-foreign",
            clientMessageID: "client-reply-foreign",
            replyToMessageID: "different-root"
        )
        try store.upsert(messages: [
            authoritative,
            staleConfirmed,
            optimistic,
            foreignReply
        ])

        let cached = try store.cachedReplyPreview(
            messageID: "root-1",
            latestReplyID: "reply-authoritative"
        )
        XCTAssertEqual(
            Set(cached.map(\.stableID)),
            Set([authoritative.stableID, optimistic.stableID])
        )
        XCTAssertEqual(
            try store.cachedReplyPreview(
                messageID: "root-1",
                latestReplyID: "reply-foreign"
            ).map(\.stableID),
            [optimistic.stableID]
        )

        var root = makeMessage(objectID: "root-1", clientMessageID: "client-root-1")
        root.latestReplyID = "reply-authoritative"
        let selected = MessagingReplyPreviewResolver.replies(for: root, from: cached)
        XCTAssertEqual(selected.map(\.stableID), [optimistic.stableID, authoritative.stableID])
    }

    func testChangedLatestPointerUsesOlderReplyAfterBatchHydration() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var root = makeMessage(
            objectID: "root-deletion",
            clientMessageID: "client-root-deletion"
        )
        root.replyCount = 2
        root.latestReplyID = "reply-newest"
        root.serverUpdatedAt = Date(timeIntervalSince1970: 100)
        var newest = makeMessage(
            objectID: "reply-newest",
            clientMessageID: "client-reply-newest",
            replyToMessageID: root.objectID
        )
        newest.clientCreatedAt = Date(timeIntervalSince1970: 300)
        newest.serverCreatedAt = newest.clientCreatedAt
        try store.upsert(messages: [root, newest])

        root.replyCount = 1
        root.latestReplyID = "reply-older"
        root.serverUpdatedAt = Date(timeIntervalSince1970: 200)
        try store.upsert(messages: [root])

        XCTAssertTrue(try store.cachedReplyPreview(
            messageID: "root-deletion",
            latestReplyID: "reply-older"
        ).isEmpty)
        XCTAssertEqual(
            ParseMessagingReplyPreviewBatch.latestReplyIDs(in: [root]),
            ["reply-older"]
        )

        var older = makeMessage(
            objectID: "reply-older",
            clientMessageID: "client-reply-older",
            replyToMessageID: root.objectID
        )
        older.clientCreatedAt = Date(timeIntervalSince1970: 200)
        older.serverCreatedAt = older.clientCreatedAt
        try store.upsert(messages: [older])

        let cached = try store.cachedReplyPreview(
            messageID: "root-deletion",
            latestReplyID: "reply-older"
        )
        XCTAssertEqual(
            MessagingReplyPreviewResolver.replies(for: root, from: cached).map(\.objectID),
            ["reply-older"]
        )
    }

    func testOutOfOrderRootEventPlansHydrationFromReconciledPointer() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var currentRoot = makeMessage(
            objectID: "root-out-of-order",
            clientMessageID: "client-root-out-of-order"
        )
        currentRoot.replyCount = 2
        currentRoot.latestReplyID = "reply-current"
        currentRoot.serverUpdatedAt = Date(timeIntervalSince1970: 300)
        try store.upsert(messages: [currentRoot])

        var staleEvent = currentRoot
        staleEvent.latestReplyID = "reply-stale"
        staleEvent.serverUpdatedAt = Date(timeIntervalSince1970: 200)
        try store.upsert(messages: [staleEvent])

        let reconciledRoot = try XCTUnwrap(
            store.cachedMessage(objectID: "root-out-of-order")
        )
        XCTAssertEqual(reconciledRoot.latestReplyID, "reply-current")
        XCTAssertEqual(
            ParseMessagingReplyPreviewBatch.latestReplyIDs(in: [reconciledRoot]),
            ["reply-current"]
        )
    }

    func testOptimisticReactionIsVisibleThroughReplyPagination() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let root = makeMessage(
            objectID: "message-reaction-root",
            clientMessageID: "client-reaction-root"
        )
        let reply = makeMessage(
            objectID: "message-reaction-reply",
            clientMessageID: "client-reaction-reply",
            replyToMessageID: root.objectID
        )
        try store.upsert(messages: [root, reply])
        _ = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "reply-reaction-1",
            conversationID: reply.conversationID,
            mutation: .setReaction(
                conversationID: reply.conversationID,
                messageID: "message-reaction-reply",
                type: MessagingReactionType.like,
                isSelected: true
            ),
            actorID: "current-user"
        ))

        let page = try store.cachedReplies(
            messageID: "message-reaction-root",
            before: nil,
            pageSize: 10
        )

        let cachedReply = try XCTUnwrap(page.items.first)
        XCTAssertEqual(cachedReply.objectID, reply.objectID)
        XCTAssertEqual(cachedReply.selectedReactionType(for: "current-user"), .like)
        XCTAssertEqual(
            cachedReply.reactionGroups(currentUserID: "current-user").first?.count,
            1
        )
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
