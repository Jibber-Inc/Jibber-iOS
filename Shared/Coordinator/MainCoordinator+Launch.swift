//
//  MainCoordinator+Launch.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/23/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat
import Intents

#if IOS
extension MainCoordinator {

    func handle(result: LaunchStatus) {
        switch result {
        case .success(let object):
            self.deepLink = object

            guard let user = User.current() else {
                self.runOnboardingFlow()
                return
            }

            if !user.isOnboarded {
                self.runOnboardingFlow()
            } else if user.status == .active {
                Task {
                    await self.runConversationListFlow()
                }.add(to: self.taskPool)
            } else if user.status == .waitlist {
                self.runWaitlistFlow()
            } else {
                self.runOnboardingFlow()
            }
        case .failed(_):
            break
        }
    }

    @MainActor
    func runConversationListFlow() async {
        if ChatClient.isConnected {
            if let coordinator = self.childCoordinator as? ConversationListCoordinator {
                if let deepLink = self.deepLink {
                    coordinator.handle(deeplink: deepLink)
                }

                await self.checkForPermissions()
            } else {
                self.removeChild()

                let startingCID = self.deepLink?.conversationId
                let startingMessageId = self.deepLink?.messageId

                let coordinator = ConversationListCoordinator(router: self.router,
                                                              deepLink: self.deepLink,
                                                              conversationMembers: [],
                                                              startingConversationId: startingCID,
                                                              startingMessageId: startingMessageId)
                self.addChildAndStart(coordinator, finishedHandler: { (_) in })

                self.router.setRootModule(coordinator)

                await self.checkForPermissions()
            }
        } else {
            try? await ChatClient.initialize(for: User.current()!)
            await self.runConversationListFlow()
        }
    }

    @MainActor
    func checkForPermissions() async {
        if INFocusStatusCenter.default.authorizationStatus != .authorized {
            self.presentPermissions()
        } else if await UserNotificationManager.shared.getNotificationSettings().authorizationStatus != .authorized {
            self.presentPermissions()
        }
    }

    @MainActor
    private func presentPermissions() {
        let coordinator = PermissionsCoordinator(router: self.router, deepLink: self.deepLink)
        self.addChildAndStart(coordinator) { [unowned self] result in
            self.router.dismiss(source: coordinator.toPresentable(), animated: true)
        }
        self.router.present(coordinator, source: self.router.topmostViewController)
    }

    func logOutChat() {
        ChatClient.shared.disconnect()
    }
}
#endif
