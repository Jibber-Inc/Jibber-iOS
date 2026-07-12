//
//  PFInstallation+Extensions.swift
//  Benji
//
//  Created by Benji Dodgson on 1/26/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

extension PFInstallation {

    static func getCurrent() async throws -> PFInstallation {
        return try await withCheckedThrowingContinuation { continuation in
            self.getCurrentInstallationInBackground().continueWith { task in
                do {
                    try Task.checkCancellation()
                } catch {
                    return continuation.resume(throwing: error)
                }

                if let installation = task.result {
                    return continuation.resume(returning: installation)
                } else {
                    return continuation.resume(throwing: ClientError.apiError(detail: "No installation was returned"))
                }
            }
        }
    }
}

extension Data {
    var hexString: String {
        let hexString = map { String(format: "%02.2hhx", $0) }.joined()
        return hexString
    }
}
