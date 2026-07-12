//
//  PFUser+Extensions.swift
//  PFUser+Extensions
//
//  Created by Martin Young on 8/15/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

extension PFUser {

    @discardableResult
    static func become(withSessionToken sessionToken: String) async throws -> PFUser {
        let user: PFUser = try await withCheckedThrowingContinuation { continuation in
            User.become(inBackground: sessionToken) { (user, error) in
                if let user = user {
                    self.storeSession(token: sessionToken)
                    return continuation.resume(returning: user)
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
        return user
    }
  
    // TODO: Move this session token to the shared keychain once retrieval works reliably.
//https://developer.apple.com/documentation/app_clips/sharing_data_between_your_app_clip_and_your_full_app
    private static func storeSession(token: String) {
        guard let sharedUserDefaults = UserDefaults(suiteName: Config.shared.environment.groupId) else {
            return
        }
        
        sharedUserDefaults.set(token, forKey: "sessionToken")
        
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
              let token = sharedUserDefaults.string(forKey: "sessionToken") else { return nil }
        sharedUserDefaults.removeObject(forKey: "sessionToken")
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
}
