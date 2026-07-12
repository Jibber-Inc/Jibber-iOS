//
//  PFConfiguration+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/13/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

extension PFConfig {
    
    var adminUserId: String? {
        return PFConfig.current()["adminUserId"] as? String
    }
    
    var welcomeConversationCID: String? {
        return PFConfig.current()["welcomeConversationCid"] as? String
    }
    
    static func awaitConfig() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            PFConfig.getInBackground { config, error in
                if let e = error {
                    continuation.resume(throwing: e)
                } else if let _ = config {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ClientError.apiError(detail: "No error or config returned."))
                }
            }
        }
    }
}
