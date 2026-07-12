//
//  Task+Extensions.swift
//  Task+Extensions
//
//  Created by Martin Young on 8/12/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

/// Preserves callback order while transferring `Sendable` values to the main
/// actor. `AsyncStream.Continuation.yield` is thread-safe and its single
/// consumer applies values serially in the order they were yielded.
final class OrderedMainActorEventRelay<Element: Sendable>: Sendable {

    private let continuation: AsyncStream<Element>.Continuation
    private let consumer: Task<Void, Never>

    init(handler: @escaping @MainActor @Sendable (Element) async -> Void) {
        let (stream, continuation) = AsyncStream<Element>.makeStream()
        self.continuation = continuation
        self.consumer = Task { @MainActor in
            for await element in stream {
                guard !Task.isCancelled else { return }
                await handler(element)
            }
        }
    }

    deinit {
        self.continuation.finish()
        self.consumer.cancel()
    }

    nonisolated func send(_ element: consuming Element) {
        self.continuation.yield(element)
    }
}

extension Task where Success == Void, Failure == Never {

    /// Creates a new task that runs the passed in closure on the MainActor. For use in non-async functions.
    static func onMainActor(body: @escaping @MainActor @Sendable () -> Success) {
        Task {
            await MainActor.run {
                body()
            }
        }
    }

    /// Creates a new task that runs the passed in closure on the MainActor. For use in async functions.
    static func onMainActorAsync(body: @escaping @MainActor @Sendable () async -> Success) {
        Task {
            await body()
        }
    }
}

extension Task where Success == Never, Failure == Never {

    /// Suspends the current task for _at least_ the given duration
    /// in seconds.
    static func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Temporarily suspends the current task for at least the specified number of seconds.
    /// Unlike Task.sleep, this function will unsuspend early if the task is cancelled.
    /// By default it checks to see if the task is cancelled every "cancelInterval" number of seconds.
    static func snooze(seconds: TimeInterval, cancelInterval: Double = 0.01) async {
        let duration = UInt64(seconds * 1_000_000_000)
        let target = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) + duration

        repeat {
            await Task.sleep(seconds: cancelInterval)
            if Task.isCancelled {
                break
            }
        } while clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) < target
    }
}
