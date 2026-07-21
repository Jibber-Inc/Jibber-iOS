//
//  PFUser+Extensions.swift
//  PFUser+Extensions
//
//  Created by Martin Young on 8/15/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

/// Moves the legacy Objective-C user callback value into its single async caller.
private struct UserTransfer: @unchecked Sendable {
    let value: PFUser
}

extension PFUser {

    private static let onboardingConversationHandoffKey = "canonicalOnboardingConversationId"
    private static let onboardingSessionHandoffKey = "sessionToken"

    @discardableResult
    static func become(
        withSessionToken sessionToken: String,
        storeForAppHandoff: Bool = true
    ) async throws -> PFUser {
        let transfer: UserTransfer = try await withCheckedThrowingContinuation { continuation in
            User.become(inBackground: sessionToken) { (user, error) in
                if let user = user {
                    if storeForAppHandoff {
                        self.storeSession(token: sessionToken)
                    }
                    return continuation.resume(returning: UserTransfer(value: user))
                } else if let error = error {
                    return continuation.resume(throwing: error)
                } else {
                    return continuation.resume(throwing: ClientError.apiError(detail: "Failed to become user."))
                }
            }
        }

#if !NOTIFICATION
        await UserNotificationManager.shared.silentRegister(withApplication: UIApplication.shared)
#endif
        return transfer.value
    }
  
    // TODO: Move this session token to the shared keychain once retrieval works reliably.
//https://developer.apple.com/documentation/app_clips/sharing_data_between_your_app_clip_and_your_full_app
    private static func storeSession(token: String) {
        guard let sharedUserDefaults = UserDefaults(suiteName: Config.shared.environment.groupId) else {
            return
        }
        
        sharedUserDefaults.set(token, forKey: self.onboardingSessionHandoffKey)
        
        // Write sensitive information you use in your App Clip to the keychain — for example, an authentication token.
//        let addSecretsQuery: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecValueData as String: token.data(using: .utf8)!,
//            kSecAttrLabel as String: "jibber-appclip-\(userObjectId)"
//        ]
//        let status = SecItemAdd(addSecretsQuery as CFDictionary, nil)
//        logDebug(status)
    }
    
    static func getStoredSessionToken() -> String? {
        guard let sharedUserDefaults = UserDefaults(suiteName: Config.shared.environment.groupId),
              let token = sharedUserDefaults.string(forKey: self.onboardingSessionHandoffKey) else {
            return nil
        }
        // Peek rather than consume. The full app clears the pair only after it
        // has authenticated, initialized messaging, and accepted the canonical
        // conversation route. A transient launch failure must remain retryable.
        return token
        // Read the sensitive information from the keychain that your App Clip stored.
//        var readSecretsQuery: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecReturnAttributes as String: true,
//            kSecAttrLabel as String: "jibber-appclip-\(currentObjectId)",
//            kSecReturnData as String: true
//        ]
//        var secretsCopy: AnyObject?
//        let status = SecItemCopyMatching(readSecretsQuery as CFDictionary, &secretsCopy)
//        logDebug(status)
//        return nil
    }

    static func storeOnboardingConversationId(_ conversationId: String) {
        guard !conversationId.isEmpty else { return }
        UserDefaults(suiteName: Config.shared.environment.groupId)?.set(
            conversationId,
            forKey: self.onboardingConversationHandoffKey
        )
    }

    static func getStoredOnboardingConversationId() -> String? {
        guard let defaults = UserDefaults(suiteName: Config.shared.environment.groupId),
              let conversationId = defaults.string(
                forKey: self.onboardingConversationHandoffKey
              ),
              !conversationId.isEmpty else { return nil }
        return conversationId
    }

    /// Explicit account transitions must not leave an App Clip credential or
    /// conversation route available to a later user of the device.
    static func clearOnboardingHandoff() {
        guard let defaults = UserDefaults(
            suiteName: Config.shared.environment.groupId
        ) else { return }
        defaults.removeObject(forKey: self.onboardingSessionHandoffKey)
        defaults.removeObject(forKey: self.onboardingConversationHandoffKey)
    }
}
