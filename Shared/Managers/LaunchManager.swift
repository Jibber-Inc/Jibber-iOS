//
//  LaunchManager.swift
//  Benji
//
//  Created by Benji Dodgson on 1/29/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import Sentry

enum LaunchActivity {
    case onboarding(phoneNumber: String?)
    case reservation(reservationId: String)
    case pass(passId: String)
    case deepLink(DeepLinkable)
}

protocol LaunchActivityHandler {
    func handle(launchActivity: LaunchActivity)
}

enum LaunchStatus {
    case success(deepLink: DeepLinkable?)
    case failed(error: ClientError?, deepLink: DeepLinkable?)
    case updateRequired(message: String)
}

protocol LaunchManagerDelegate: AnyObject {
    func launchManager(_ manager: LaunchManager, didReceive activity: LaunchActivity)
}

class LaunchManager {
    
    static let shared = LaunchManager()
    
    weak var delegate: LaunchManagerDelegate?

    func launchApp(with deepLink: DeepLinkable?) async -> LaunchStatus {
        // Initialize Parse if necessary
        Config.shared.initializeParseIfNeeded(includeBundleId: false)
        
        Task.onMainActorAsync {
            SentrySDK.start { options in
                options.dsn = "https://674f5b98c542435fadeffd8828582b32@o1232170.ingest.sentry.io/6380104"
                options.debug = false//Config.shared.environment == .staging // Enabled debug when first installing is always helpful
                // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
                // We recommend adjusting this value in production.
                options.tracesSampleRate = 1.0
            }
        }

#if !NOTIFICATION
        // Silently register for notifications every launch.
        if let user = User.current(), user.isAuthenticated {
            // Ensure that the user object is up to date.
            _ = try? await user.fetchInBackground()

            // Pre-load contacts
            _ = ContactsManager.shared

            do {
                async let first: Void
                = UserNotificationManager.shared.silentRegister(withApplication: UIApplication.shared)
                // Initialize the people store
                async let second: Void = PeopleStore.shared.initializeIfNeeded()
                let _: [Void] = try await [first, second]

                // Update the timeZone
                user.timeZone = TimeZone.current.identifier
                user.saveEventually()
            } catch {
                if error.code != 141 {
                    await ToastScheduler.shared.schedule(toastType: .error(error))
                }
                return LaunchStatus.failed(error: ClientError.error(error: error), deepLink: deepLink)
            }
        }
#endif
        // Increase the size of the cache so it can accommodate a decent amound of media.
        URLCache.shared.memoryCapacity = 512 * 1024 * 1024 // 512 MB

        // Initializes the analytics manager
        _ = AnalyticsManager.shared
        
        let launchStatus = await self.initializeUserData(with: deepLink)

        try? await PFConfig.awaitConfig()
        return launchStatus
    }

    private func initializeUserData(with deeplink: DeepLinkable?) async -> LaunchStatus {
        guard let user = User.current() else {
            // There is no user object yet, there's nothing to initialize.
            return .success(deepLink: deeplink)
        }

#if !APPCLIP && !NOTIFICATION
        // Messaging is a launch-critical service. Capability/schema/minimum-
        // version failures deliberately stop here so an incompatible client
        // can never enter the app and issue unsupported writes.
        do {
            try await ParseMessagingManager.shared.initialize(for: user)
        } catch {
            if let messagingError = error as? ParseMessagingManagerError {
                switch messagingError {
                case .appUpdateRequired, .unsupportedSchemaVersion:
                    return .updateRequired(
                        message: messagingError.localizedDescription
                    )
                default:
                    break
                }
            }
            return .failed(error: ClientError.error(error: error), deepLink: deeplink)
        }

        return await self.finishMessagingLaunch(for: user, deepLink: deeplink)
#else
        return .success(deepLink: deeplink)
#endif
    }
    
    func continueUser(activity: NSUserActivity) {
        if let launchActivity = activity.launchActivity {
            self.delegate?.launchManager(self, didReceive: launchActivity)
        }
    }
}

extension LaunchManager {

#if !APPCLIP && !NOTIFICATION
    func finishMessagingLaunch(for user: User, deepLink: DeepLinkable?) async -> LaunchStatus {
        if let user = User.current(), user.isAuthenticated {
            await UserNotificationManager.shared.silentRegister(withApplication: UIApplication.shared)
        }

        return .success(deepLink: deepLink)
    }
#endif
}
