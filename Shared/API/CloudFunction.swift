//
//  CloudCalls.swift
//  Benji
//
//  Created by Benji Dodgson on 9/10/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

/// Moves one Objective-C cloud callback result into its single async caller.
private struct CloudValueTransfer: @unchecked Sendable {
    let value: Any
}

protocol CloudFunction {

    associatedtype ReturnType

    func makeRequest(andUpdate statusables: [Statusable],
                     viewsToIgnore: [UIView]) async throws -> ReturnType
}

extension CloudFunction {

    func makeRequest(andUpdate statusables: [Statusable],
                     params: [String : Any],
                     callName: String,
                     delayInterval: TimeInterval = 2.0,
                     viewsToIgnore: [UIView]) async throws -> Any {

        // Trigger the loading event for all statusables before starting the
        // request. These are main-actor UI state transitions.
        for statusable in statusables {
            await statusable.handleEvent(status: .loading)
        }

        // Reference the statusables weakly in case they are deallocated before the signal finishes.
        let weakStatusables: [WeakAnyStatusable] = statusables.map { (statusable)  in
            return WeakAnyStatusable(statusable)
        }

        do {
            let transfer = try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<CloudValueTransfer, Error>) in
                PFCloud.callFunction(inBackground: callName,
                                     withParameters: params) { (object, error) in

                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let value = object {
                        continuation.resume(returning: CloudValueTransfer(value: value))
                    } else {
                        continuation.resume(throwing: ClientError.apiError(detail: "Request failed"))
                    }
                }
            })

            try Task.checkCancellation()

            for weakStatusable in weakStatusables {
                guard let statusable = weakStatusable.value else { continue }
                await statusable.handleEvent(status: .saved)
            }

            // A saved status is temporary so we set it to complete after a short delay
            Task {
                await Task.snooze(seconds: delayInterval)
                for weakStatusable in weakStatusables {
                    guard let statusable = weakStatusable.value else { continue }
                    await statusable.handleEvent(status: .complete)
                }
            }

            return transfer.value
        } catch {
            await SessionManager.shared.handleParse(error: error)
            for weakStatusable in weakStatusables {
                guard let statusable = weakStatusable.value else { continue }
                await statusable.handleEvent(status: .error(error.localizedDescription))
            }
            throw(error)
        }
    }
}
