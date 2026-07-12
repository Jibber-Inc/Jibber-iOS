//
//  MomentCoordinator+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/6/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

#if IOS
extension MomentCoordinator {
    func presentMomentCapture() {
        let coordinator = MomentCaptureCoordinator(router: self.router, deepLink: self.deepLink)
        
        self.present(coordinator) { [unowned self] result in
            self.momentVC.showMomentIfAvailable()
        }
    }
    
    func presentProfile(for person: PersonType) {
        
        let coordinator = ProfileCoordinator(with: person, router: self.router, deepLink: self.deepLink)
        
        self.present(coordinator) { [unowned self] result in
            switch result {
            case .conversation(let conversationId):
                self.finishFlow(with: .conversation(conversationId))
            case .openReplies(let message):
                self.finishFlow(with: .openReplies(message))
            case .message(let message):
                self.finishFlow(with: .message(message))
            }
        }
    }
    
    func presentComments() {
        let coordinator = CommentsCoordinator(router: self.router,
                                              deepLink: self.deepLink,
                                              conversationId: self.moment.commentsId,
                                              startingMessageId: nil,
                                              openReplies: false)
        self.present(coordinator)
    }
    
    func presentReactions() {
        let coordinator = ReactionsDetailCoordinator(router: self.router,
                                                     deepLink: self.deepLink,
                                                     moment: self.moment)
        self.present(coordinator)
    }
    
    func presentAddExpression() {
        let coordinator = ExpressionCoordinator(router: self.router,
                                                deepLink: self.deepLink)
        
        self.present(coordinator) { [unowned self] result in
            guard let expression = result else { return }
            
            expression.emotions.forEach { emotion in
                AnalyticsManager.shared.trackEvent(type: .emotionSelected,
                                                   properties: ["value": emotion.rawValue])
            }
            
            let controller = ConversationController.controller(for: self.moment.commentsId)
            
            Task {
                do {
                    try await controller.add(expression: expression)
                } catch {
                    logError(error)
                }
            }
        }
    }
    
    func showCommentsAlert() {
        let alert = UIAlertController(title: "Comments Unavailable",
                                      message: "To view comments, record today's moment.",
                                      preferredStyle: .alert)
        
        let record = UIAlertAction(title: "Record", style: .default) { [unowned self] _ in
            self.presentMomentCapture()
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in }
        
        alert.addAction(record)
        alert.addAction(cancel)
        
        self.router.topmostViewController.present(alert, animated: true)
    }
    
    func showReactionsAlert() {
        let alert = UIAlertController(title: "Reactions Unavailable",
                                      message: "To view reactions, record today's moment.",
                                      preferredStyle: .alert)
        
        let record = UIAlertAction(title: "Record", style: .default) { [unowned self] _ in
            self.presentMomentCapture()
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in }
        
        alert.addAction(record)
        alert.addAction(cancel)
        
        self.router.topmostViewController.present(alert, animated: true)
    }
    
    func presentShareSheet() {
        Task {
            await self.moment.prepareMetadata()
            
            let activityVC = ActivityViewController(with: self, activityItems: [self.moment])
            self.router.topmostViewController.present(activityVC, animated: true)
        }
    }
}

extension MomentCoordinator: MomentContentViewDelegate {
    func momentContentViewDidSelectCapture(_ view: MomentContentView) {
        self.presentMomentCapture()
    }
    
    func momentContent(_ view: MomentContentView, didSelectPerson person: PersonType) {
        self.presentProfile(for: person)
    }
}

extension MomentCoordinator: ActivityViewControllerDelegate {
    
    func activityView(_ controller: ActivityViewController, didCompleteWith result: ActivityViewController.Result) {
        
    }
}
#endif
