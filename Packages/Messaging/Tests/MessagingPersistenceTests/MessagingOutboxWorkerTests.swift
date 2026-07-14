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
