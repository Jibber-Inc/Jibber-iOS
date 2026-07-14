import XCTest
import MessagingContracts
@testable import MessagingPersistence

final class MessagingOutboxWorkerTests: XCTestCase {
    func testSuccessfulDrainConfirmsOptimisticMessage() async throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let draft = MessagingMessageDraft(
            conversationID: "conversation-1",
            clientMessageID: "client-worker-1",
            content: MessagingMessageContent(kind: .text, text: "Hello")
        )
        _ = try store.stageSend(draft: draft, authorID: "user-1")
        let confirmed = MessagingMessageSnapshot(
            objectID: "message-1",
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
        let remote = StubMessageRepository(result: .message(confirmed))
        let worker = MessagingOutboxWorker(
            store: store,
            remote: remote,
            errorClassifier: StubErrorClassifier(isRetryable: false)
        )

        let report = try await worker.drainOnce()

        XCTAssertEqual(report.succeeded, 1)
        XCTAssertEqual(
            try store.cachedMessage(clientMessageID: draft.clientMessageID)?.objectID,
            "message-1"
        )
        XCTAssertNil(try store.outboxEntry(idempotencyKey: draft.clientMessageID))
    }

    func testRetryableFailureSchedulesBackoffAndKeepsOptimisticMessage() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = try GRDBMessagingStore(inMemory: .init())
        let draft = MessagingMessageDraft(
            conversationID: "conversation-1",
            clientMessageID: "client-worker-2",
            clientCreatedAt: now,
            content: MessagingMessageContent(kind: .text, text: "Hello")
        )
        _ = try store.stageSend(draft: draft, authorID: "user-1")
        let remote = StubMessageRepository(error: URLError(.notConnectedToInternet))
        let worker = MessagingOutboxWorker(
            store: store,
            remote: remote,
            errorClassifier: StubErrorClassifier(isRetryable: true),
            clock: FixedClock(now: now),
            retryPolicy: MessagingRetryPolicy(
                maximumAttempts: 3,
                initialDelay: 2,
                maximumDelay: 30
            )
        )

        let report = try await worker.drainOnce()

        XCTAssertEqual(report.retryScheduled, 1)
        let entry = try XCTUnwrap(store.outboxEntry(idempotencyKey: draft.clientMessageID))
        XCTAssertEqual(entry.state, .retryScheduled)
        XCTAssertEqual(entry.nextAttemptAt, now.addingTimeInterval(2))
        XCTAssertEqual(
            try store.cachedMessage(clientMessageID: draft.clientMessageID)?.localState,
            .retrying
        )
    }

    func testSuccessfulReactionDrainReplacesOptimisticStateWithAuthoritativeSnapshot() async throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let message = makeMessage(objectID: "message-reaction-success")
        try store.upsert(messages: [message])
        let entry = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "reaction-success-1",
            conversationID: message.conversationID,
            mutation: .setReaction(
                conversationID: message.conversationID,
                messageID: "message-reaction-success",
                type: MessagingReactionType.like,
                isSelected: true
            ),
            actorID: "current-user"
        ))
        var authoritative = message
        authoritative.serverUpdatedAt = Date(timeIntervalSince1970: 300)
        authoritative.reactions = [MessagingReactionSnapshot(
            objectID: "reaction-server-1",
            messageID: "message-reaction-success",
            userID: "current-user",
            type: MessagingReactionType.like.rawValue,
            createdAt: Date(timeIntervalSince1970: 200),
            serverUpdatedAt: Date(timeIntervalSince1970: 300)
        )]
        let worker = MessagingOutboxWorker(
            store: store,
            remote: StubMessageRepository(result: .message(authoritative)),
            errorClassifier: StubErrorClassifier(isRetryable: false)
        )

        let report = try await worker.drainOnce()

        XCTAssertEqual(report.succeeded, 1)
        let cached = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-success")
        )
        XCTAssertEqual(cached.reactions, authoritative.reactions)
        XCTAssertNil(cached.reactions.first?.localMutationID)
        XCTAssertNil(cached.reactions.first?.localMutationState)
        XCTAssertNil(try store.outboxEntry(idempotencyKey: entry.idempotencyKey))
    }

    func testReactionResultMismatchBlocksAndMarksOptimisticValueFailed() async throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let message = makeMessage(objectID: "message-reaction-mismatch")
        try store.upsert(messages: [message])
        let entry = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "reaction-mismatch-1",
            conversationID: message.conversationID,
            mutation: .setReaction(
                conversationID: message.conversationID,
                messageID: "message-reaction-mismatch",
                type: MessagingReactionType.love,
                isSelected: true
            ),
            actorID: "current-user"
        ))
        let worker = MessagingOutboxWorker(
            store: store,
            remote: StubMessageRepository(result: .message(message)),
            errorClassifier: StubErrorClassifier(isRetryable: false)
        )

        let report = try await worker.drainOnce()

        XCTAssertEqual(report.blocked, 1)
        XCTAssertEqual(
            try store.outboxEntry(idempotencyKey: entry.idempotencyKey)?.state,
            .blocked
        )
        let reaction = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-mismatch")?.reactions.first
        )
        XCTAssertEqual(reaction.localMutationState, .selectionFailed)
        XCTAssertTrue(try XCTUnwrap(reaction.lastFailureDescription).contains(
            "reactionResultMismatch"
        ))
    }

    func testReactionSwitchReusesServerObjectThenRemovesCleanly() async throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var message = makeMessage(objectID: "message-reaction-switch")
        message.reactions = [MessagingReactionSnapshot(
            objectID: "reaction-like",
            messageID: "message-reaction-switch",
            userID: "current-user",
            type: MessagingReactionType.like.rawValue,
            createdAt: Date(timeIntervalSince1970: 150),
            serverUpdatedAt: Date(timeIntervalSince1970: 150)
        )]
        try store.upsert(messages: [message])
        let select = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "reaction-switch-select",
            conversationID: message.conversationID,
            mutation: .setReaction(
                conversationID: message.conversationID,
                messageID: "message-reaction-switch",
                type: .love,
                isSelected: true
            ),
            actorID: "current-user"
        ))
        let optimisticSwitch = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-switch")
        )
        XCTAssertEqual(optimisticSwitch.reactions.count, 1)
        XCTAssertEqual(optimisticSwitch.reactions[0].objectID, "reaction-like")
        XCTAssertEqual(optimisticSwitch.reactions[0].reactionType, .love)
        XCTAssertEqual(optimisticSwitch.reactions[0].localMutationState, .selecting)

        var selected = message
        selected.serverUpdatedAt = Date(timeIntervalSince1970: 200)
        selected.reactions[0].type = MessagingReactionType.love.rawValue
        selected.reactions[0].serverUpdatedAt = Date(timeIntervalSince1970: 200)
        var removed = selected
        removed.serverUpdatedAt = Date(timeIntervalSince1970: 250)
        removed.reactions[0].isDeleted = true
        removed.reactions[0].deletedAt = Date(timeIntervalSince1970: 250)
        removed.reactions[0].serverUpdatedAt = Date(timeIntervalSince1970: 250)
        let worker = MessagingOutboxWorker(
            store: store,
            remote: SequencedMessageRepository(results: [
                .message(selected),
                .message(removed),
            ]),
            errorClassifier: StubErrorClassifier(isRetryable: false)
        )

        let firstReport = try await worker.drainOnce()
        XCTAssertEqual(firstReport.succeeded, 1)
        XCTAssertNil(try store.outboxEntry(idempotencyKey: select.idempotencyKey))
        let authoritativeSwitch = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-switch")
        )
        XCTAssertEqual(authoritativeSwitch.reactions.count, 1)
        XCTAssertEqual(authoritativeSwitch.reactions[0].objectID, "reaction-like")
        XCTAssertEqual(authoritativeSwitch.reactions[0].reactionType, .love)
        XCTAssertNil(authoritativeSwitch.reactions[0].localMutationState)

        let remove = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "reaction-switch-remove",
            conversationID: message.conversationID,
            mutation: .setReaction(
                conversationID: message.conversationID,
                messageID: "message-reaction-switch",
                type: .love,
                isSelected: false
            ),
            actorID: "current-user"
        ))

        let secondReport = try await worker.drainOnce()
        XCTAssertEqual(secondReport.succeeded, 1)
        XCTAssertNil(try store.outboxEntry(idempotencyKey: remove.idempotencyKey))
        let authoritativeRemoval = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-switch")
        )
        XCTAssertEqual(authoritativeRemoval.reactions.count, 1)
        XCTAssertFalse(authoritativeRemoval.reactions[0].isActive)
        XCTAssertNil(authoritativeRemoval.reactions[0].localMutationState)
    }

    func testOlderSelectionConfirmationCannotClearNewerTypeFailureState() async throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        var message = makeMessage(objectID: "message-reaction-rapid-switch")
        message.reactions = [MessagingReactionSnapshot(
            objectID: "reaction-selection",
            messageID: "message-reaction-rapid-switch",
            userID: "current-user",
            type: MessagingReactionType.like.rawValue,
            createdAt: Date(timeIntervalSince1970: 150),
            serverUpdatedAt: Date(timeIntervalSince1970: 150)
        )]
        try store.upsert(messages: [message])
        _ = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "reaction-rapid-love",
            conversationID: message.conversationID,
            mutation: .setReaction(
                conversationID: message.conversationID,
                messageID: "message-reaction-rapid-switch",
                type: .love,
                isSelected: true
            ),
            actorID: "current-user"
        ))
        let latest = try store.enqueue(MessagingOutboxEntry(
            idempotencyKey: "reaction-rapid-dislike",
            conversationID: message.conversationID,
            mutation: .setReaction(
                conversationID: message.conversationID,
                messageID: "message-reaction-rapid-switch",
                type: .dislike,
                isSelected: true
            ),
            actorID: "current-user"
        ))

        var authoritativeLove = message
        authoritativeLove.serverUpdatedAt = Date(timeIntervalSince1970: 200)
        authoritativeLove.reactions[0].type = MessagingReactionType.love.rawValue
        authoritativeLove.reactions[0].serverUpdatedAt = Date(timeIntervalSince1970: 200)
        let worker = MessagingOutboxWorker(
            store: store,
            remote: SequencedMessageRepository(results: [
                .message(authoritativeLove),
                .message(authoritativeLove),
            ]),
            errorClassifier: StubErrorClassifier(isRetryable: false)
        )

        let firstReport = try await worker.drainOnce()
        XCTAssertEqual(firstReport.succeeded, 1)
        var cached = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-rapid-switch")
        )
        XCTAssertEqual(cached.reactions.count, 1)
        XCTAssertEqual(cached.reactions[0].reactionType, .dislike)
        XCTAssertEqual(cached.reactions[0].localMutationID, latest.idempotencyKey)
        XCTAssertEqual(cached.reactions[0].localMutationState, .selecting)

        let secondReport = try await worker.drainOnce()
        XCTAssertEqual(secondReport.blocked, 1)
        cached = try XCTUnwrap(
            store.cachedMessage(objectID: "message-reaction-rapid-switch")
        )
        XCTAssertEqual(cached.reactions.count, 1)
        XCTAssertEqual(cached.reactions[0].reactionType, .dislike)
        XCTAssertEqual(cached.reactions[0].localMutationID, latest.idempotencyKey)
        XCTAssertEqual(cached.reactions[0].localMutationState, .selectionFailed)
    }

    func testInvalidationPreventsLateTransportCallbackFromWritingCache() async throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let draft = MessagingMessageDraft(
            conversationID: "conversation-1",
            clientMessageID: "client-worker-invalidated",
            content: MessagingMessageContent(kind: .text, text: "Hello")
        )
        _ = try store.stageSend(draft: draft, authorID: "user-1")
        let confirmed = MessagingMessageSnapshot(
            objectID: "message-invalidated",
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
        let remote = SuspendedMessageRepository()
        let worker = MessagingOutboxWorker(
            store: store,
            remote: remote,
            errorClassifier: StubErrorClassifier(isRetryable: false)
        )
        let drainTask = Task<Void, Error> {
            _ = try await worker.drainOnce()
        }

        await remote.waitUntilPerformStarted()
        worker.invalidate()
        await remote.finish(with: .message(confirmed))

        do {
            try await drainTask.value
            XCTFail("An invalidated worker must not complete a late callback.")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertNil(
            try store.cachedMessage(clientMessageID: draft.clientMessageID)?.objectID
        )
        XCTAssertEqual(
            try store.outboxEntry(idempotencyKey: draft.clientMessageID)?.state,
            .inFlight
        )
    }

    func testDrainDoesNotInheritMainActorExecutor() async throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let clock = ThreadRecordingClock(now: Date(timeIntervalSince1970: 1_000))
        let worker = MessagingOutboxWorker(
            store: store,
            remote: StubMessageRepository(),
            errorClassifier: StubErrorClassifier(isRetryable: false),
            clock: clock
        )

        let drainTask = Task { @MainActor in
            try await worker.drainOnce()
        }
        _ = try await drainTask.value

        XCTAssertEqual(clock.wasAccessedOnMainThread, false)
    }

    private func makeMessage(objectID: MessagingMessageID) -> MessagingMessageSnapshot {
        MessagingMessageSnapshot(
            objectID: objectID,
            clientMessageID: "client-\(objectID)",
            conversationID: "conversation-1",
            authorID: "author-1",
            clientCreatedAt: Date(timeIntervalSince1970: 100),
            serverCreatedAt: Date(timeIntervalSince1970: 100),
            serverUpdatedAt: Date(timeIntervalSince1970: 100),
            content: MessagingMessageContent(kind: .text, text: "Hello"),
            deliveryKind: .conversational,
            localState: .confirmed
        )
    }
}

private actor SuspendedMessageRepository: MessagingMessageRepository {
    private var didStartPerform = false
    private var continuation: CheckedContinuation<MessagingMutationResult, Error>?

    func messages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        MessagingPage(items: [], nextCursor: nil, hasMore: false)
    }

    func replies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        MessagingPage(items: [], nextCursor: nil, hasMore: false)
    }

    func pinnedMessages(
        conversationID: MessagingConversationID
    ) async throws -> [MessagingMessageSnapshot] {
        []
    }

    func perform(
        _ mutation: MessagingMutation,
        idempotencyKey: String
    ) async throws -> MessagingMutationResult {
        self.didStartPerform = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilPerformStarted() async {
        while !self.didStartPerform {
            await Task.yield()
        }
    }

    func finish(with result: MessagingMutationResult) {
        self.continuation?.resume(returning: result)
        self.continuation = nil
    }
}

private actor SequencedMessageRepository: MessagingMessageRepository {
    private var results: [MessagingMutationResult]

    init(results: [MessagingMutationResult]) {
        self.results = results
    }

    func messages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        MessagingPage(items: [], nextCursor: nil, hasMore: false)
    }

    func replies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        MessagingPage(items: [], nextCursor: nil, hasMore: false)
    }

    func pinnedMessages(
        conversationID: MessagingConversationID
    ) async throws -> [MessagingMessageSnapshot] {
        []
    }

    func perform(
        _ mutation: MessagingMutation,
        idempotencyKey: String
    ) async throws -> MessagingMutationResult {
        guard !results.isEmpty else { return .acknowledged }
        return results.removeFirst()
    }
}

private final class StubMessageRepository: MessagingMessageRepository {
    private let result: MessagingMutationResult?
    private let error: Error?

    init(result: MessagingMutationResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func messages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        MessagingPage(items: [], nextCursor: nil, hasMore: false)
    }

    func replies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        MessagingPage(items: [], nextCursor: nil, hasMore: false)
    }

    func pinnedMessages(
        conversationID: MessagingConversationID
    ) async throws -> [MessagingMessageSnapshot] {
        []
    }

    func perform(
        _ mutation: MessagingMutation,
        idempotencyKey: String
    ) async throws -> MessagingMutationResult {
        if let error = error { throw error }
        return result ?? .acknowledged
    }
}

private struct StubErrorClassifier: MessagingErrorClassifying {
    let isRetryable: Bool
    func isRetryableMessagingError(_ error: Error) -> Bool { isRetryable }
}

private struct FixedClock: MessagingClock {
    let now: Date
}

private final class ThreadRecordingClock: MessagingClock, @unchecked Sendable {
    private let lock = NSLock()
    private let value: Date
    private var recordedMainThreadAccess: Bool?

    init(now: Date) {
        self.value = now
    }

    var now: Date {
        self.lock.lock()
        self.recordedMainThreadAccess = Thread.isMainThread
        self.lock.unlock()
        return self.value
    }

    var wasAccessedOnMainThread: Bool? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.recordedMainThreadAccess
    }
}
