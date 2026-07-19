//
//  WaitlistCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 4/12/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import ParseCore
import UIKit
import StoreKit

class WaitlistCoordinator: PresentableCoordinator<Void> {
    
    lazy var waitlistVC = WaitlistViewController()
    private var isPresentingMomentExperience = false
    
    override func toPresentable() -> PresentableCoordinator<Void>.DismissableVC {
        return self.waitlistVC
    }
    
    override func start() {
        super.start()
        self.isPresentingMomentExperience = self.deepLink?.deepLinkTarget == .moment
        self.setupHandlers()
        
        Task {
            if let reservationId = self.deepLink?.reservationId,
                let reservation = try? await Reservation.getObject(with: reservationId),
               let createById = reservation.createdBy?.objectId,
               let person = await PeopleStore.shared.getPerson(withPersonId: createById) {
                
                self.waitlistVC.personView.set(person: person)
                self.waitlistVC.personView.isVisible = true
                self.waitlistVC.descriptionLabel.setText("You now have access to join \(person.givenName) on Jibber!")
                self.waitlistVC.view.setNeedsLayout()
                
            } else if let passId = self.deepLink?.passId,
                        let pass = try? await Pass.getObject(with: passId),
                      let ownerId = pass.owner?.objectId,
                      let person = await PeopleStore.shared.getPerson(withPersonId: ownerId) {
                
                self.waitlistVC.personView.set(person: person)
                self.waitlistVC.personView.isVisible = true
                self.waitlistVC.descriptionLabel.setText("\(person.givenName) has granted you access to Jibber! Join below.")
                self.waitlistVC.descriptionLabel.setText("")
                self.waitlistVC.view.setNeedsLayout()
            } else if let creatorId = self.deepLink?.reservationCreatorId {
                await self.personalizeLanding(with: creatorId)
            } else if let target = self.deepLink?.deepLinkTarget, target == .moment {
                await self.presentMoment(with: deepLink)
            }
        }
    }

    @MainActor
    private func personalizeLanding(with userId: String) async {
        guard let inviter = try? await User.getObject(with: userId) else { return }
        self.waitlistVC.personView.set(person: inviter)
        self.waitlistVC.personView.isVisible = true
        self.waitlistVC.descriptionLabel.setText(
            "You're connected with \(inviter.givenName) on Jibber."
        )
        self.waitlistVC.view.setNeedsLayout()
    }
    
    private func setupHandlers() {
        self.waitlistVC.shouldDisplayUpdateOverlay = { [unowned self] in
            if !self.isPresentingMomentExperience {
                self.presentSKOverlay()
            }
        }
        
        self.waitlistVC.button.didSelect { [unowned self] in
            guard let user = User.current() else { return }
            switch user.status {
            case .active:
                self.finishFlow(with: ())
            case .waitlist:
                self.presentShareSheet()
            default:
                break
            }
        }
    }
    
    private func presentShareSheet() {
        Task {
            await self.waitlistVC.button.handleEvent(status: .loading)
            guard let pass = try? await Pass.fetchPass() else { return }
            await pass.prepareMetadata()

            let ac = ActivityViewController(with: self, activityItems: [pass])
            
            Task.onMainActor {
                self.router.topmostViewController.present(ac, animated: true) {
                    Task {
                        await self.waitlistVC.button.handleEvent(status: .complete)
                    }
                }
            }
        }
    }
    
    func presentMoment(with deepLink: DeepLinkable?) async {
        
        guard let moment = try? await Moment.getObject(with: deepLink?.momentId) else {
            return
        }
            
        Task.onMainActor { [self] in
            let coordinator = MomentCoordinator(moment: moment,
                                                router: self.router,
                                                deepLink: deepLink)
            self.addChildAndStart(coordinator, finishedHandler: { [unowned self] (_) in
                self.router.topmostViewController.dismiss(animated: true) {
                    #if APPCLIP
                    Task {
                        await self.acceptMomentInvitation(moment)
                    }
                    #else
                    self.presentSKOverlay()
                    #endif
                }
            })
            
            self.router.present(coordinator, source: self.waitlistVC)
        }
    }

    @MainActor
    private func acceptMomentInvitation(_ moment: Moment) async {
        guard let momentId = moment.objectId else { return }
        self.isPresentingMomentExperience = false
        await self.waitlistVC.button.handleEvent(status: .loading)
        do {
            let response = try await AcceptMomentInvitation(momentId: momentId)
                .makeRequest(andUpdate: [], viewsToIgnore: [self.waitlistVC.view])
            if let authorId = moment.author?.objectId {
                await self.personalizeLanding(with: authorId)
            }
            AnalyticsManager.shared.trackEvent(
                type: .appClipConnectionCompleted,
                properties: [
                    "allocation": response["reservationAllocation"] as? String ?? "unknown",
                    "kind": "moment"
                ]
            )
            await self.waitlistVC.button.handleEvent(status: .complete)
            self.presentSKOverlay()
        } catch {
            await self.waitlistVC.button.handleEvent(status: .complete)
            await ToastScheduler.shared.schedule(toastType: .error(error))
        }
    }
    
    func presentSKOverlay() {
    #if APPCLIP
        guard let scene = self.waitlistVC.view.window?.windowScene else { return }
        let config = SKOverlay.AppClipConfiguration(position: .bottom)
        let overlay = SKOverlay(configuration: config)
        overlay.present(in: scene)
        AnalyticsManager.shared.trackEvent(
            type: .appClipUpgradeOverlayPresented,
            properties: nil
        )
    #endif
    }
}

extension WaitlistCoordinator: ActivityViewControllerDelegate {
    
    func activityView(_ controller: ActivityViewController, didCompleteWith result: ActivityViewController.Result) {
        if result.didShare {
            Task {
                await upgradeUser()
            }
        }
    }
    
    private func upgradeUser() async {
        Task {
            await self.waitlistVC.button.handleEvent(status: .loading)

            do {
                try await FinalizeOnboarding(reservationId: "",
                                             passId: "",
                                             forceUpgrade: true)
                .makeRequest(andUpdate: [], viewsToIgnore: [self.waitlistVC.view])
            } catch {
                await ToastScheduler.shared.schedule(toastType: .error(error))
            }
            
            await self.waitlistVC.button.handleEvent(status: .loading)
            
            self.finishFlow(with: ())
        }
    }
}
