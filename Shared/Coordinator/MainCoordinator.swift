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

/// Resumes the launch bridge exactly once, including when its task is cancelled
/// before the child coordinator finishes.
private final class LaunchDeepLinkContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<LaunchDeepLinkTransfer, Never>?
    private var pendingValue: LaunchDeepLinkTransfer?
    private var isFinished = false

    func install(_ continuation: CheckedContinuation<LaunchDeepLinkTransfer, Never>) {
        self.lock.lock()

        if self.isFinished {
            let value = self.pendingValue
            self.lock.unlock()

            if let value {
                continuation.resume(returning: value)
            }
        } else {
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func resume(returning value: LaunchDeepLinkTransfer) {
        self.lock.lock()

        guard !self.isFinished else {
            self.lock.unlock()
            return
        }

        self.isFinished = true
        self.pendingValue = value
        let continuation = self.continuation
        self.continuation = nil
        self.lock.unlock()

        continuation?.resume(returning: value)
    }
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

            let launchContinuation = LaunchDeepLinkContinuation()
            let transfer: LaunchDeepLinkTransfer = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    launchContinuation.install(continuation)

                    guard !Task.isCancelled else {
                        launchContinuation.resume(returning: LaunchDeepLinkTransfer(value: nil))
                        return
                    }

                    let launchCoordinator = LaunchCoordinator(router: self.router, deepLink: self.deepLink)
                    self.router.setRootModule(launchCoordinator)
                    self.addChildAndStart(launchCoordinator) { result in
                        switch result {
                        case .success(let deepLink):
                            launchContinuation.resume(returning: LaunchDeepLinkTransfer(value: deepLink))
                        case .failed:
                            self.logOut()
                            launchContinuation.resume(returning: LaunchDeepLinkTransfer(value: nil))
                        }
                    }
                }
            } onCancel: {
                launchContinuation.resume(returning: LaunchDeepLinkTransfer(value: nil))
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
            } else if case .some(.reservation(let reservationId)) = self.launchActivity {
                var invitation = DeepLinkObject(target: .reservation)
                invitation.reservationId = reservationId
                self.handleAppClip(deepLink: invitation)
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
        self.addChildAndStart(coordinator, finishedHandler: { [unowned self] deepLink in
            // Preserve contextual invitation metadata through the App Clip
            // landing state and the equivalent full-app destination.
            self.handle(deeplink: deepLink ?? DeepLinkObject(target: .home))
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
