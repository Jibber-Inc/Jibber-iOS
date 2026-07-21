//
//  PFConfiguration+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/13/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

let onboardingMessagingConfigKey = "onboardingMessagingV1"
let conversationOnboardingConfigKey = "conversationOnboardingV1"

private struct PFConfigTransfer: @unchecked Sendable {
    let value: PFConfig
}

extension PFConfig {
    
    var adminUserId: String? {
        return PFConfig.current()["adminUserId"] as? String
    }
    
    var welcomeConversationCID: String? {
        return PFConfig.current()["welcomeConversationCid"] as? String
    }

    var onboardingMessagingJSONObject: Any? {
        self[onboardingMessagingConfigKey]
    }

    /// Defaults off so released clients keep the legacy coordinator until the
    /// versioned backend endpoints and schema are deployed in that environment.
    var isConversationOnboardingEnabled: Bool {
        self[conversationOnboardingConfigKey] as? Bool ?? false
    }
    
    static func awaitConfig() async throws -> PFConfig {
        let transfer: PFConfigTransfer = try await withCheckedThrowingContinuation { continuation in
            PFConfig.getInBackground { config, error in
                if let e = error {
                    continuation.resume(throwing: e)
                } else if let config {
                    continuation.resume(returning: PFConfigTransfer(value: config))
                } else {
                    continuation.resume(throwing: ClientError.apiError(detail: "No error or config returned."))
                }
            }
        }
        return transfer.value
    }
}
