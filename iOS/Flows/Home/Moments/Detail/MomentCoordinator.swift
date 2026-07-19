//
//  MomentCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/3/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import ParseCore
import UIKit

enum ProfileResult {
    case conversation(String)
    #if IOS
    case openReplies(Messageable)
    case message(Messageable)
    #endif
}

class MomentCoordinator: PresentableCoordinator<ProfileResult?>, DeepLinkHandler {
    
    let moment: Moment
    #if IOS
    var didOfferContextualConnection = false
    #endif
    
    lazy var momentVC: MomentViewController = {
        return MomentViewController(with: self.moment)
    }()
    
    init(moment: Moment,
         router: CoordinatorRouter,
         deepLink: DeepLinkable?) {
        
        self.moment = moment
        
        super.init(router: router, deepLink: deepLink)
    }
    
    override func toPresentable() -> DismissableVC {
        return self.momentVC
    }
    
    override func start() {
        super.start()
        
        self.momentVC.contentView.delegate = self
        
        self.momentVC.footerView.reactionsView.reactionsView.didSelect { [unowned self] in
            #if IOS
            guard let controller = self.momentVC.footerView.reactionsView.controller else { return }
            if let expressions = controller.conversation?.expressions, expressions.count > 0 {
                if self.moment.isAvailable {
                    self.presentReactions()
                } else {
                    self.showReactionsAlert()
                }
            }
            #elseif APPCLIP
            self.presentOnboardingAlert(action: "view_reactions")
            #endif
        }
        
        self.momentVC.footerView.reactionsView.button.didSelect { [unowned self] in
            #if IOS
            if self.moment.isAvailable {
                self.presentAddExpression()
            } else {
                self.showReactionsAlert()
            }
            #elseif APPCLIP
            self.presentOnboardingAlert(action: "add_expression")
            #endif
        }
        
        self.momentVC.footerView.commentsLabel.didSelect { [unowned self] in
            #if IOS
            if self.moment.isAvailable {
                self.presentComments()
            } else {
                self.showCommentsAlert()
            }
            #elseif APPCLIP
            self.presentOnboardingAlert(action: "comments")
            #endif
        }
        
        self.momentVC.footerView.shareButton.didSelect { [unowned self] in
            #if IOS
            self.presentShareSheet()
            #elseif APPCLIP
            self.presentOnboardingAlert(action: "reshare")
            #endif
        }
        
        if let deepLink = self.deepLink {
            self.handle(deepLink: deepLink)
        }

        #if IOS
        if self.deepLink?.deepLinkTarget == .moment {
            Task { @MainActor [weak self] in
                await Task.sleep(seconds: 0.5)
                await self?.presentContextualConnectionPromptIfNeeded()
            }
        }
        #endif
    }
    
    func handle(deepLink: DeepLinkable) {
        guard let target = deepLink.deepLinkTarget else {
            return
        }
        
        #if IOS
        switch target {
        case .comment:
            Task.onMainActorAsync {
                await Task.sleep(seconds: 0.25)
                self.presentComments()
            }
        case .capture:
            self.presentMomentCapture()
        default:
            break
        }
        #endif
    }
    
    func present<ChildResult>(_ coordinator: PresentableCoordinator<ChildResult>,
                              finishedHandler: ((ChildResult) -> Void)? = nil,
                              cancelHandler: (() -> Void)? = nil) {
        self.removeChild()
        
        coordinator.toPresentable().dismissHandlers.append { [unowned self] in
            self.momentVC.footerView.reactionsView.reactionsView.expressionVideoView.shouldPlay = true
            self.momentVC.contentView.play()
        }
        
        self.addChildAndStart(coordinator) { [unowned self] result in
            self.momentVC.dismiss(animated: true) {
                finishedHandler?(result)
            }
        }
        
        self.momentVC.footerView.reactionsView.reactionsView.expressionVideoView.shouldPlay = false
        self.momentVC.contentView.pause()
        
        self.router.present(coordinator, source: self.momentVC, cancelHandler: cancelHandler)
    }
    
    #if APPCLIP
    func presentOnboardingAlert(action: String) {
        AnalyticsManager.shared.trackEvent(
            type: .appClipGatedActionTapped,
            properties: ["action": action]
        )

        let authorName = self.moment.author?.givenName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = (authorName?.isEmpty == false ? authorName : nil) ?? "this person"
        let isActiveUser = User.current()?.isAuthenticated == true
            && User.current()?.status == .active
        let alert = UIAlertController(
            title: isActiveUser ? "Connect with \(firstName)?" : "Join \(firstName) on Jibber",
            message: isActiveUser
                ? "Connect to unlock authenticated Moment interactions in the full Jibber app."
                : "Continue to connect and unlock Moment interactions. You can return to this Moment at any time.",
                                      preferredStyle: .alert)
        
        let login = UIAlertAction(
            title: isActiveUser ? "Connect" : "Continue",
            style: .default
        ) { [unowned self] _ in
            self.finishFlow(with: nil)
        }
        
        let cancel = UIAlertAction(title: "Not Now", style: .cancel) { _ in }
        
        alert.addAction(login)
        alert.addAction(cancel)
        
        self.router.topmostViewController.present(alert, animated: true)
    }
    #endif
}

#if APPCLIP
extension MomentCoordinator: MomentContentViewDelegate {
    func momentContentViewDidSelectCapture(_ view: MomentContentView) {
        self.presentOnboardingAlert(action: "capture")
    }

    func momentContent(_ view: MomentContentView, didSelectPerson person: PersonType) {
        self.presentOnboardingAlert(action: "profile")
    }
}
#endif
