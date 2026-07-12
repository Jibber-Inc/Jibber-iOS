//
//  PFInstallation+Extensions.swift
//  Benji
//
//  Created by Benji Dodgson on 1/26/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

/// Transfers the legacy Objective-C installation returned by Bolts to the
/// single async caller that requested it.
private struct InstallationTransfer: @unchecked Sendable {
    let value: PFInstallation
}

extension PFInstallation {

    static func getCurrent() async throws -> PFInstallation {
        let transfer: InstallationTransfer = try await withCheckedThrowingContinuation { continuation in
            self.getCurrentInstallationInBackground().continueWith { task in
                do {
                    try Task.checkCancellation()
                } catch {
                    return continuation.resume(throwing: error)
                }

                if let installation = task.result {
                    return continuation.resume(returning: InstallationTransfer(value: installation))
                } else {
                    return continuation.resume(throwing: ClientError.apiError(detail: "No installation was returned"))
                }
            }
        }
        return transfer.value
    }
}

extension Data {
    var hexString: String {
        let hexString = map { String(format: "%02.2hhx", $0) }.joined()
        return hexString
    }
}
