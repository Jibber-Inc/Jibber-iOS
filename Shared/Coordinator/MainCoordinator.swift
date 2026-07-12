//
//  MainCoordinator.swift
//  Benji
//
//  Created by Benji Dodgson on 6/22/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit
import ParseCore
import Coordinator

/// Moves a callback-owned deep link into the launch task that requested it.
private struct LaunchDeepLinkTransfer: @unchecked Sendable {
    let value: DeepLinkable?
}

class MainCoordinator: BaseCoordinator<Void> {
    
    var launchActivity: LaunchActivity?
    var messagingLaunchAlert: UIAlertController?

    override func start() {
        super.start()

        SessionManager.shared.didReceiveInvalidSessionError = { [unowned self] _ in
            Task.onMainActor {
                self.showSessionErrorAlert()
            }
        }
        
        SessionManager.shared.didRecieveReuestToLogOut = { [unowned self] in
            Task.onMainActor {
                self.logOut()
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

    /// A task to start the launch flow and handle a deep link. If the task is cancelled, the deep link will not be handled.
    private(set) var launchAndDeepLinkTask: Task<Void, Never>?
    private func runLaunchFlow() {
        self.launchAndDeepLinkTask?.cancel()

        self.launchAndDeepLinkTask = Task { [weak self] in
            guard let self else { return }
            
            let transfer: LaunchDeepLinkTransfer = await withCheckedContinuation { continuation in
                let launchCoordinator = LaunchCoordinator(router: self.router, deepLink: self.deepLink)
                self.router.setRootModule(launchCoordinator)
                self.addChildAndStart(launchCoordinator) { result in
                    
                    switch result {
                    case .success(let deepLink):
                        continuation.resume(returning: LaunchDeepLinkTransfer(value: deepLink))
                    case .failed:
                        self.logOut()
                        continuation.resume(returning: LaunchDeepLinkTransfer(value: nil))
                    }
                }
            }
            let deepLink = transfer.value

            // Don't handle the launch status if the task was cancelled.
            guard !Task.isCancelled else { return }

        #if IOS
            if let deepLink = deepLink {
                self.handle(deeplink: deepLink)
            } else {
                self.handle(deeplink: DeepLinkObject(target: .home))
            }
        #elseif APPCLIP
            // Code your App Clip may access.
            if let deepLink = deepLink {
                self.handleAppClip(deepLink: deepLink)
            } else if let user = User.current(), user.isOnboarded {
                self.handle(deeplink: DeepLinkObject(target: .waitlist))
            } else {
                self.handleAppClip(deepLink: DeepLinkObject(target: .login))
            }
        #endif
        }
    }

    @MainActor
    func handle(deeplink: DeepLinkable) {
        self.deepLink = deeplink

        // NOTE: Regardless of the deep link, the user needs to be created and activated to get
        // to the whole app.
        
        // If no user object has been created, allow the user to do so now.
        guard let user = User.current(), user.isAuthenticated else {
            self.runOnboardingFlow(with: deeplink)
            return
        }

        // If ther user didn't finish onboarding, redirect them to onboarding
        if !user.isOnboarded {
            self.runOnboardingFlow(with: deeplink)
            return
        }
        
        // Check if the user is on the waitlist.
        if user.status == .waitlist {
            self.runWaitlistFlow(with: deeplink)
            return
        }

        // As a final catch-all, make sure the user is fully activated.
        guard user.status == .active else {
            self.runOnboardingFlow(with: deeplink)
            return
        }

        // Clean up the deep link when we're done
        defer {
            self.deepLink = nil
        }
        
        self.handle(deeplink)
    }
    
    private func handle(_ link: DeepLinkable) {
        guard let target = link.deepLinkTarget else { return }

        // Now attempt to handle the deeplink.
        switch target {
        case .home, .conversation, .wallet, .profile, .reservation, .thread, .capture, .comment, .moment:
        #if IOS
            Task {
                await self.runHomeFlow(with: link)
            }
        #elseif APPCLIP
            self.runWaitlistFlow(with: link)
        #endif
        case .login:
            self.runOnboardingFlow(with: link)
        case .waitlist:
            self.runWaitlistFlow(with: link)
        }
    }

    func runOnboardingFlow(with deepLink: DeepLinkable?) {
        self.removeChild()
        let coordinator = OnboardingCoordinator(router: self.router,
                                                deepLink: deepLink)
        self.router.setRootModule(coordinator, animated: true)
        self.addChildAndStart(coordinator, finishedHandler: { [unowned self] (_) in
            // Attempt to take the user to the room screen after onboarding is complete.
            self.handle(deeplink: DeepLinkObject(target: .home))
        })
        
        if let launchActivity = self.launchActivity {
            coordinator.handle(launchActivity: launchActivity)
        }
    }
    
    func runWaitlistFlow(with deepLink: DeepLinkable?) {
        self.removeChild()
        let coordinator = WaitlistCoordinator(router: self.router,
                                                deepLink: deepLink)
        self.router.setRootModule(coordinator, animated: true)
        self.addChildAndStart(coordinator, finishedHandler: { [unowned self] (_) in
            // Attempt to take the user to the room screen after onboarding is complete.
            self.handle(deeplink: DeepLinkObject(target: .home))
        })
    }

    func showSessionErrorAlert() {
        let alert = UIAlertController(title: "🙀",
                                      message: "Someone tripped over a 🐈 and ☠️ the mainframe.",
                                      preferredStyle: .alert)
        let ok = UIAlertAction(title: "Ok", style: .default) { [unowned self] (_) in
            self.logOut()
        }
        
        alert.addAction(ok)

        if self.router.topmostViewController is UIAlertController {
        } else {
            self.router.topmostViewController.present(alert, animated: true, completion: nil)
        }
    }

    func logOut() {
#if IOS
        self.logOutChat()
#endif
        User.logOut()
        self.deepLink = nil
        if let child = self.childCoordinator as? Presentable {
            child.toPresentable().dismiss(animated: true)
        }
        self.removeChild()
        
        self.runOnboardingFlow(with: nil)
    }
}

#if IOS

// MARK: - UserNotificationManagerDelegate

extension MainCoordinator: UserNotificationManagerDelegate {

    func userNotificationManager(willHandle deeplink: DeepLinkable) {
        let transfer = LaunchDeepLinkTransfer(value: deeplink)
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Cancelling other deeplink calls.
            self.launchAndDeepLinkTask?.cancel()

            // Wait until the launch is finished.
            await self.launchAndDeepLinkTask?.value

            if let deeplink = transfer.value {
                self.handle(deeplink: deeplink)
            }
        }
    }
}
#endif
