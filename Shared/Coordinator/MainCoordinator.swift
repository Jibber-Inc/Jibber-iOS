//
//  MainCoordinator.swift
//  Benji
//
//  Created by Benji Dodgson on 6/22/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit
import Parse

class MainCoordinator: Coordinator<Void> {

    override func start() {
        super.start()

        SessionManager.shared.didReceiveInvalidSessionError = { [unowned self] _ in
            Task.onMainActor {
                self.showLogOutAlert()
            }
        }

        LaunchManager.shared.delegate = self
        self.subscribeToUserUpdates()
        
#if IOS
        UserNotificationManager.shared.delegate = self
        ToastScheduler.shared.delegate = self
#endif

        self.runLaunchFlow()
    }

    private func runLaunchFlow() {
        let launchCoordinator = LaunchCoordinator(router: self.router, deepLink: self.deepLink)
        self.router.setRootModule(launchCoordinator)
        self.addChildAndStart(launchCoordinator) { [unowned self] launchStatus in
#if IOS
            self.handle(result: launchStatus)
#elseif APPCLIP
            // Code your App Clip may access.
            self.handleAppClip(result: launchStatus)
#endif
        }
    }

    func handle(result: LaunchStatus) {
        switch result {
        case .success(let deepLink):
            if let deepLink = deepLink {
                self.handle(deeplink: deepLink)
            } else {
                self.handle(deeplink: DeepLinkObject(target: .conversation))
            }
        case .failed(_):
            break
        }
    }

    func handle(deeplink: DeepLinkable) {
        self.deepLink = deeplink

        // NOTE: Regardless of the deep link, the user needs to be created and activated to get
        // to the whole app.

        // If no user object has been created, allow the user to do so now.
        guard let user = User.current(), user.isAuthenticated else {
            self.runOnboardingFlow()
            return
        }

        // If ther user didn't finish onboarding, redirect them to onboarding
        if !user.isOnboarded {
            self.runOnboardingFlow()
        } else if user.status == .waitlist {
            // The user finished onboarding but is on the waitlist so don't proceed to the main app.
            self.runWaitlistFlow()
        }

        // As a final catch-all, make sure the user is fully activated.
        guard user.status == .active else {
            self.runOnboardingFlow()
            return
        }

        // Clean up the deep link when we're done
        defer {
            self.deepLink = nil
        }

        guard let target = deeplink.deepLinkTarget else { return }

        // Now attempt to handle the deeplink.
        switch target {
        case .home, .conversation:
#if IOS
            Task {
                await self.runConversationListFlow()
            }
#endif
        case .login:
            self.runOnboardingFlow()
        case .reservation:
#if IOS
            Task {
                await self.runConversationListFlow()
            }
#endif
            self.runOnboardingFlow()
        }
    }

    func runOnboardingFlow() {
        if let onboardingCoordinator = self.childCoordinator as? OnboardingCoordinator {
            onboardingCoordinator.handle(deeplink: self.deepLink)
        } else {
            let coordinator = OnboardingCoordinator(router: self.router,
                                                    deepLink: self.deepLink)
            self.router.setRootModule(coordinator, animated: true)
            self.addChildAndStart(coordinator, finishedHandler: { [unowned self] (_) in
                if User.current()?.status == .waitlist {
                    self.runWaitlistFlow()
                } else {
                    self.subscribeToUserUpdates()

#if IOS
                    Task {
                        await self.runConversationListFlow()
                    }.add(to: self.taskPool)
#endif
                }
            })
        }
    }

    func runWaitlistFlow() {
        let waitlistCoordinator = WaitlistCoordinator(router: self.router, deepLink: nil)
        self.router.setRootModule(waitlistCoordinator)
        self.addChildAndStart(waitlistCoordinator) { _ in

        }
    }

    func showLogOutAlert() {
        let alert = UIAlertController(title: "🙀",
                                      message: "Someone tripped over a 🐈 and ☠️ the mainframe.",
                                      preferredStyle: .alert)
        let ok = UIAlertAction(title: "Ok", style: .default) { (_) in
            self.logOut()
        }
        
        alert.addAction(ok)

        if self.router.topmostViewController is UIAlertController {
        } else {
            self.router.topmostViewController.present(alert, animated: true, completion: nil)
        }
    }

    private func logOut() {
#if IOS
        self.logOutChat()
#endif
        User.logOut()
        self.deepLink = nil
        self.removeChild()
        self.runOnboardingFlow()
    }
}

#if IOS
extension MainCoordinator: UserNotificationManagerDelegate {

    nonisolated func userNotificationManager(willHandle deeplink: DeepLinkable) {
        Task.onMainActor {
            self.handle(deeplink: deeplink)
        }
    }
}
#endif
