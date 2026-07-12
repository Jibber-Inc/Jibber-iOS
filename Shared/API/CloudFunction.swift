//
//  CloudCalls.swift
//  Benji
//
//  Created by Benji Dodgson on 9/10/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

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

        Task {
            // Trigger the loading event for all statusables
            await withTaskGroup(of: Void.self) { group in
                for statusable in statusables {
                    group.addTask {
                        await statusable.handleEvent(status: .loading)
                    }
                }
            }
        }

        // Reference the statusables weakly in case they are deallocated before the signal finishes.
        let weakStatusables: [WeakAnyStatusable] = statusables.map { (statusable)  in
            return WeakAnyStatusable(statusable)
        }

        do {
            let result = try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Any, Error>) in
                PFCloud.callFunction(inBackground: callName,
                                     withParameters: params) { (object, error) in

                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let value = object {
                        continuation.resume(returning: value)
                    } else {
                        continuation.resume(throwing: ClientError.apiError(detail: "Request failed"))
                    }
                }
            })

            try Task.checkCancellation()

            await withTaskGroup(of: Void.self) { group in
                for weakStatusable in weakStatusables {
                    group.addTask {
                        guard let statusable = weakStatusable.value else { return }
                        await statusable.handleEvent(status: .saved)
                    }
                }
            }

            // A saved status is temporary so we set it to complete after a short delay
            Task {
                await Task.snooze(seconds: delayInterval)
                await withTaskGroup(of: Void.self) { group in
                    for weakStatusable in weakStatusables {
                        group.addTask {
                            guard let statusable = weakStatusable.value else { return }
                            await statusable.handleEvent(status: .complete)
                        }
                    }
                }
            }

            return result
        } catch {
            SessionManager.shared.handleParse(error: error)
            await withTaskGroup(of: Void.self) { group in
                for weakStatusable in weakStatusables {
                    group.addTask {
                        guard let statusable = weakStatusable.value else { return }
                        await statusable.handleEvent(status: .error(error.localizedDescription))
                    }
                }
            }
            throw(error)
        }
    }
}
