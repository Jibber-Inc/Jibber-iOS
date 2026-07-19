//
//  MomentCoordinator+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/6/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import ParseCore

#if IOS
extension MomentCoordinator {
    @MainActor
    func presentContextualConnectionPromptIfNeeded() async {
        guard !self.didOfferContextualConnection,
              let currentUser = User.current(),
              currentUser.isAuthenticated,
              currentUser.status == .active,
              let author = try? await self.moment.author?.retrieveDataIfNeeded(),
              let authorId = author.objectId,
              authorId != currentUser.objectId else {
            return
        }

        let fromAuthor = Connection.query()!
            .whereKey(ConnectionKey.from.rawValue, equalTo: author)
            .whereKey(ConnectionKey.to.rawValue, equalTo: currentUser)
            .whereKey(ConnectionKey.status.rawValue, equalTo: Connection.Status.accepted.rawValue)
        let fromRecipient = Connection.query()!
            .whereKey(ConnectionKey.from.rawValue, equalTo: currentUser)
            .whereKey(ConnectionKey.to.rawValue, equalTo: author)
            .whereKey(ConnectionKey.status.rawValue, equalTo: Connection.Status.accepted.rawValue)
        let existingConnections = try? await PFQuery
            .orQuery(withSubqueries: [fromAuthor, fromRecipient])
            .findObjectsInBackground()
        guard existingConnections?.isEmpty != false else { return }

        self.didOfferContextualConnection = true
        let firstName = author.givenName.isEmpty ? "this person" : author.givenName.capitalized
        let alert = UIAlertController(
            title: "Connect with \(firstName)?",
            message: "Accept this Moment invitation without leaving what was shared.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
            guard let self, let momentId = self.moment.objectId else { return }
            Task { @MainActor in
                do {
                    let response = try await AcceptMomentInvitation(momentId: momentId)
                        .makeRequest(andUpdate: [], viewsToIgnore: [self.momentVC.view])
                    AnalyticsManager.shared.trackEvent(
                        type: .appClipConnectionCompleted,
                        properties: [
                            "allocation": response["reservationAllocation"] as? String ?? "unknown",
                            "kind": "moment"
                        ]
                    )
                    await ToastScheduler.shared.schedule(
                        toastType: .success(.personCropCircle, "Connected with \(firstName)")
                    )
                } catch {
                    await ToastScheduler.shared.schedule(toastType: .error(error))
                }
            }
        })
        self.router.topmostViewController.present(alert, animated: true)
    }

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
            AnalyticsManager.shared.trackEvent(
                type: .appClipShareCreated,
                properties: ["kind": "moment"]
            )
            
            let activityVC = ActivityViewController(
                with: self,
                activityItems: self.moment.activityItems()
            )
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
