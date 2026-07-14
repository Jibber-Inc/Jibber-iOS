//
//  MessagingOutboxWorker.swift
//  MessagingPersistence
//

import Foundation
import MessagingContracts

public struct MessagingRetryPolicy: Hashable {
    public var maximumAttempts: Int
    public var initialDelay: TimeInterval
    public var maximumDelay: TimeInterval

    public init(
        maximumAttempts: Int = 8,
        initialDelay: TimeInterval = 1,
        maximumDelay: TimeInterval = 5 * 60
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.initialDelay = max(0, initialDelay)
        self.maximumDelay = max(initialDelay, maximumDelay)
    }

    public func delay(afterAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let exponent = min(attempt - 1, 30)
        return min(maximumDelay, initialDelay * pow(2, Double(exponent)))
    }
}

public struct MessagingOutboxDrainReport: Hashable, Sendable {
    public var succeeded: Int
    public var retryScheduled: Int
    public var blocked: Int

    public init(succeeded: Int = 0, retryScheduled: Int = 0, blocked: Int = 0) {
        self.succeeded = succeeded
        self.retryScheduled = retryScheduled
        self.blocked = blocked
    }
}

/// Runs at most one head operation per conversation. The store query prevents
/// later operations in a conversation from overtaking an earlier retry.
public final class MessagingOutboxWorker: @unchecked Sendable {
    private let store: MessagingLocalStore
    private let remote: MessagingMessageRepository
    private let errorClassifier: MessagingErrorClassifying
    private let clock: MessagingClock
    private let retryPolicy: MessagingRetryPolicy
    private let validityLock = NSLock()
    private var isValid = true

    public init(
        store: MessagingLocalStore,
        remote: MessagingMessageRepository,
        errorClassifier: MessagingErrorClassifying,
        clock: MessagingClock = SystemMessagingClock(),
        retryPolicy: MessagingRetryPolicy = MessagingRetryPolicy()
    ) {
        self.store = store
        self.remote = remote
        self.errorClassifier = errorClassifier
        self.clock = clock
        self.retryPolicy = retryPolicy
    }

    /// Prevents a transport callback that resumes after logout from writing
    /// into a cache that has already been purged or reopened for a new session.
    /// Store mutations run under the same short lock, so invalidation either
    /// precedes a mutation or waits for that synchronous mutation to finish.
    public func invalidate() {
        self.validityLock.lock()
        self.isValid = false
        self.validityLock.unlock()
    }

    @discardableResult
    @concurrent
    public func drainOnce(limit: Int = 8) async throws -> MessagingOutboxDrainReport {
        let entries = try self.withValidState {
            try self.store.readyOutboxEntries(at: self.clock.now, limit: limit)
        }
        var report = MessagingOutboxDrainReport()
        for entry in entries {
            var inFlight = entry
            inFlight.state = .inFlight
            try self.withValidState {
                try self.store.updateOutboxEntry(inFlight)
            }

            do {
                let result = try await remote.perform(
                    inFlight.mutation,
                    idempotencyKey: inFlight.idempotencyKey
                )
                try self.withValidState {
                    try self.apply(result: result, for: inFlight)
                }
                report.succeeded += 1
            } catch {
                try self.withValidState {
                    var failed = inFlight
                    failed.attemptCount += 1
                    failed.lastErrorDescription = String(describing: error)
                    let canRetry = self.errorClassifier.isRetryableMessagingError(error)
                        && failed.attemptCount < self.retryPolicy.maximumAttempts
                    if canRetry {
                        failed.state = .retryScheduled
                        failed.nextAttemptAt = self.clock.now.addingTimeInterval(
                            self.retryPolicy.delay(afterAttempt: failed.attemptCount)
                        )
                        report.retryScheduled += 1
                    } else {
                        failed.state = .blocked
                        report.blocked += 1
                    }
                    try self.store.updateOutboxEntry(failed)
                    try self.updateOptimisticMessage(for: failed)
                }
            }
        }
        return report
    }

    private func withValidState<Value>(
        _ operation: () throws -> Value
    ) throws -> Value {
        self.validityLock.lock()
        defer { self.validityLock.unlock() }
        guard self.isValid else { throw CancellationError() }
        return try operation()
    }

    private func apply(
        result: MessagingMutationResult,
        for entry: MessagingOutboxEntry
    ) throws {
        switch (entry.mutation, result) {
        case (.send, .message(let message)):
            try store.confirm(message: message, idempotencyKey: entry.idempotencyKey)
        case (
            .setReaction(_, _, let type, let isSelected),
            .message(let message)
        ):
            if let actorID = entry.actorID {
                guard message.reactions.contains(where: {
                    $0.userID == actorID
                        && $0.type == type
                        && $0.isActive == isSelected
                }) else {
                    throw MessagingOutboxWorkerError.reactionResultMismatch
                }
            }
            try store.upsert(messages: [message])
            try store.removeOutboxEntry(id: entry.id)
        case (_, .message(let message)):
            try store.upsert(messages: [message])
            try store.removeOutboxEntry(id: entry.id)
        case (_, .conversation(let conversation)):
            try store.upsert(conversations: [conversation])
            try store.removeOutboxEntry(id: entry.id)
        case (_, .member(let member)):
            try store.upsert(members: [member])
            try store.removeOutboxEntry(id: entry.id)
        case (.send, .acknowledged):
            throw MessagingOutboxWorkerError.sendDidNotReturnMessage
        case (.setReaction, .acknowledged):
            throw MessagingOutboxWorkerError.reactionDidNotReturnMessage
        case (_, .acknowledged):
            try store.removeOutboxEntry(id: entry.id)
        }
    }

    private func updateOptimisticMessage(for entry: MessagingOutboxEntry) throws {
        guard case .send(let draft, _) = entry.mutation,
              var message = try store.cachedMessage(clientMessageID: draft.clientMessageID) else {
            return
        }
        message.localState = entry.state == .blocked ? .failed : .retrying
        message.lastFailureDescription = entry.lastErrorDescription
        try store.upsert(messages: [message])
    }
}

public enum MessagingOutboxWorkerError: Error, Equatable {
    case sendDidNotReturnMessage
    case reactionDidNotReturnMessage
    case reactionResultMismatch
}
