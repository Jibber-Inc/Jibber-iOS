//
//  MainCoordinator+Launch.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/23/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

extension MainCoordinator {

    @MainActor
    func runHomeFlow(with deepLink: DeepLinkable?) async {
        // Launch normally initializes messaging. Re-establish it here only
        // when a restored coordinator reaches Home without the matching user.
        if let user = User.current(),
           !ParseMessagingManager.shared.isInitialized
            || ParseMessagingManager.shared.authenticatedUserID != user.objectId {
            try? await ParseMessagingManager.shared.initialize(for: user)
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

    func logOutChat() {
        Task { @MainActor in
            JibberMessagingClient.shared.disconnect()
            await ParseMessagingManager.shared.disconnect()
        }
    }
}
