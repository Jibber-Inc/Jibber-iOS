//
//  MainCoordinator+Launch.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/23/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

extension MainCoordinator {

    @MainActor
    func runHomeFlow(with deepLink: DeepLinkable?) async {
        guard let user = User.current(), user.isAuthenticated else {
            self.runOnboardingFlow(with: deepLink)
            return
        }

        // Launch normally initializes messaging. Re-establish it here only
        // when a restored coordinator reaches Home without the matching user.
        if !ParseMessagingManager.shared.isInitialized
            || ParseMessagingManager.shared.authenticatedUserID != user.objectId {
            do {
                try await ParseMessagingManager.shared.initialize(for: user)
            } catch {
                self.presentMessagingLaunchBlocker(error, deepLink: deepLink)
                return
            }
        }

        guard ParseMessagingManager.shared.isInitialized,
              ParseMessagingManager.shared.authenticatedUserID == user.objectId else {
            self.presentMessagingLaunchBlocker(
                ParseMessagingManagerError.notInitialized,
                deepLink: deepLink
            )
            return
        }
        
        if let coordinator = self.furthestChild as? LaunchActivityHandler,
           let launchActivity = self.launchActivity {
            coordinator.handle(launchActivity: launchActivity)
        } else if let coordinator = self.furthestChild as? DeepLinkHandler,
           let link = deepLink {
            coordinator.handle(deepLink: link)
        } else {
            let coordinator = HomeCoordinator(router: self.router, deepLink: self.deepLink)
            self.addChildAndStart(coordinator, finishedHandler: { (_) in})
            self.router.setRootModule(coordinator)
            if let activity = self.launchActivity {
                coordinator.handle(launchActivity: activity)
            } else if let deepLink = deepLink {
                coordinator.handle(deepLink: deepLink)
            }
        }
    }

    @MainActor
    private func presentMessagingLaunchBlocker(
        _ error: Error,
        deepLink: DeepLinkable?
    ) {
        guard self.messagingLaunchAlert == nil else { return }

        let isUpdateRequired: Bool
        if let messagingError = error as? ParseMessagingManagerError {
            switch messagingError {
            case .appUpdateRequired, .unsupportedSchemaVersion:
                isUpdateRequired = true
            default:
                isUpdateRequired = false
            }
        } else {
            isUpdateRequired = false
        }

        let alert: UIAlertController
        if isUpdateRequired {
            alert = UIAlertController(
                title: "Update Required",
                message: error.localizedDescription
                    + " Please update Jibber from the App Store to continue.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                // Dismissing the explanation never enters Home. A later
                // navigation attempt will re-check compatibility and block.
                self?.messagingLaunchAlert = nil
            })
        } else {
            alert = UIAlertController(
                title: "Messaging Unavailable",
                message: "Check your connection and please try again.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.messagingLaunchAlert = nil
                Task { @MainActor [weak self] in
                    await self?.runHomeFlow(with: deepLink)
                }
            })
        }

        self.messagingLaunchAlert = alert
        self.router.topmostViewController.present(alert, animated: true)
    }

    func logOutChat() {
        Task { @MainActor in
            JibberMessagingClient.shared.disconnect()
            await ParseMessagingManager.shared.disconnect()
        }
    }
}
