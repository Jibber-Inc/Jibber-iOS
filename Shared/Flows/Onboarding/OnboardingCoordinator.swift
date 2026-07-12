//
//  LoginCoordinator.swift
//  Benji
//
//  Created by Benji Dodgson on 8/10/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import PhoneNumberKit
import ParseCore
import Combine
import Intents
import Coordinator

class OnboardingCoordinator: PresentableCoordinator<DeepLinkable?> {
    
    private lazy var onboardingVC = OnboardingViewController(with: self)
    
    override func toPresentable() -> DismissableVC {
        return self.onboardingVC
    }
    
    override func start() {
        self.setInitialOnboardingContent()
        self.handle(deeplink: self.deepLink)
    }
    
    func handle(deeplink: DeepLinkable?) {
        guard let link = deeplink else { return }
        
        if let target = link.deepLinkTarget, target == .moment {
            self.presentMoment(with: link)
        } else {
            self.onboardingVC.reservationId = link.reservationId ?? ""
            self.onboardingVC.passId = link.passId ?? ""
            self.onboardingVC.updateUI()
        }
    }
    
    // MARK: - Onboarding Flow Logic
    
    private func setInitialOnboardingContent() {
        let userStatus = User.current()?.status
        
        let initialContent: OnboardingContent
        switch userStatus {
        case .needsVerification, .inactive, .waitlist, .none:
            initialContent = .welcome(self.onboardingVC.welcomeVC)
        case .active:
            self.finishFlow(with: nil)
            return
        }
        
        self.onboardingVC.switchTo(initialContent)
    }
    
    /// Returns the content for the first incompleted onboarding step in the onboarding sequence.
    private func getNextIncompleteOnboardingContent() -> OnboardingContent? {
        guard let current = User.current(), let status = current.status else {
            // If there is no user, then they'll need to provide a phone number to create one.
            return .phone(self.onboardingVC.phoneVC)
        }
        
        switch status {
        case .needsVerification:
            return .code(self.onboardingVC.codeVC)
        case .inactive:
            if !current.fullName.isValidFullName {
                return .name(self.onboardingVC.nameVC)
            } else if current.smallImage.isNil {
#if targetEnvironment(simulator)
                return nil
#else
                return .photo(self.onboardingVC.photoVC)
#endif
            } else {
                return nil
            }
        case .active, .waitlist:
            // Active users don't need to do onboarding.
            return nil
        }
    }
    
    func presentMoment(with deepLink: DeepLinkable?) {
        
        Task.onMainActorAsync { [self] in
            guard let moment = try? await Moment.getObject(with: deepLink?.momentId) else {
                return
            }
            
            await Task.sleep(seconds: 0.5)
            
            let coordinator = MomentCoordinator(moment: moment,
                                                router: self.router,
                                                deepLink: deepLink)
            self.addChildAndStart(coordinator, finishedHandler: { [unowned self] (_) in
                self.router.topmostViewController.dismiss(animated: true) {
                    self.goToNextContentOrFinish()
                }
            })
            
            self.router.present(coordinator, source: self.onboardingVC)
        }
    }
}

extension OnboardingCoordinator: OnboardingViewControllerDelegate {
    
    // MARK: - User Info Entry Flow
    
    func onboardingViewControllerDidStartOnboarding(_ controller: OnboardingViewController) {
        let phoneVC = self.onboardingVC.phoneVC
        self.onboardingVC.switchTo(.phone(phoneVC))
    }
    
    func onboardingViewControllerDidSelectRSVP(_ controller: OnboardingViewController) {
        
        let alertController = UIAlertController(title: "RSVP",
                                                message: "Please enter the code you received.",
                                                preferredStyle: .alert)
        
        alertController.addTextField { (textField : UITextField!) -> Void in
            textField.placeholder = "Code"
        }
        let saveAction = UIAlertAction(title: "Confirm", style: .default, handler: { alert -> Void in
            if let textField = alertController.textFields?.first,
               let text = textField.text,
               !text.isEmpty {
                controller.handle(launchActivity: .reservation(reservationId: text))
            }
        })
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: {
            (action : UIAlertAction!) -> Void in
            
        })
        
        alertController.addAction(saveAction)
        alertController.addAction(cancelAction)
        
        controller.present(alertController, animated: true, completion: nil)
    }
    
    func onboardingViewController(_ controller: OnboardingViewController, didEnter phoneNumber: PhoneNumber) {
        let codeVC = self.onboardingVC.codeVC
        codeVC.phoneNumber = phoneNumber
        self.onboardingVC.switchTo(.code(codeVC))
    }
    
    func onboardingViewControllerDidVerifyCode(_ controller: OnboardingViewController,
                                               andReturnCID cid: String?) {
        self.goToNextContentOrFinish()
    }
    
    func onboardingViewController(_ controller: OnboardingViewController, didEnterName name: String) {
        Task {
            do {
                guard let user = User.current() else { return }
                user.formatName(from: name)
                try await user.saveLocalThenServer()
                
                self.goToNextContentOrFinish()
            } catch {
                await ToastScheduler.shared.schedule(toastType: .error(error))
            }
        }
    }
    
    func onboardingViewControllerDidTakePhoto(_ controller: OnboardingViewController) {
        self.goToNextContentOrFinish()
    }
    
    private func goToNextContentOrFinish() {
        if let nextContent = self.getNextIncompleteOnboardingContent() {
            self.onboardingVC.switchTo(nextContent)
        } else if let user = User.current() {
            switch user.status {
            case .needsVerification, .none, .active:
                self.finishFlow(with: nil)
            case .inactive, .waitlist:
                self.finalizeOnboarding(user: user)
            }
        }
    }
    
    func finalizeOnboarding(user: User) {
        Task {
            self.onboardingVC.showLoading()
            
            do {
                try await FinalizeOnboarding(reservationId: self.onboardingVC.reservationId,
                                             passId: self.onboardingVC.passId)
                .makeRequest(andUpdate: [], viewsToIgnore: [self.onboardingVC.view])
            } catch {
                await ToastScheduler.shared.schedule(toastType: .error(error))
            }
            
            AnalyticsManager.shared.trackEvent(type: .finalizedOnboarding, properties: ["status": user.status?.rawValue ?? ""])
            await self.onboardingVC.hideLoading()
            
            var deepLink = DeepLinkObject(target: .home)
            deepLink.reservationId = self.onboardingVC.reservationId
            deepLink.passId = self.onboardingVC.passId
            self.finishFlow(with: deepLink)
        }
    }
}

// MARK: - Launch Activity Handling

extension OnboardingCoordinator: LaunchActivityHandler {
    
    func handle(launchActivity: LaunchActivity) {
        self.onboardingVC.handle(launchActivity: launchActivity)
    }
}
