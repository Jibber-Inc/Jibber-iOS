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
import UIKit

class OnboardingCoordinator: PresentableCoordinator<DeepLinkable?> {
    
    private lazy var onboardingVC = OnboardingViewController(with: self)
    private var canonicalSyncRequest = 0
    private var canonicalSyncTask: Task<Void, Never>?
    private var isFinishingCanonicalFlow = false
    private var isAwaitingAuthoritativeRestore = false

    /// MainCoordinator starts this coordinator synchronously, then may still
    /// have a retained universal-link activity to dispatch. Expose the
    /// authoritative restore decision so that stale launch input cannot race
    /// the server-owned onboarding session.
    var isRestoringCanonicalOnboarding: Bool {
        self.shouldRestoreCanonicalOnboarding
    }
    
    override func toPresentable() -> DismissableVC {
        return self.onboardingVC
    }
    
    override func start() {
#if DEBUG
        if self.startOnboardingPreviewIfRequested() {
            return
        }
#endif

        if self.shouldRestoreCanonicalOnboarding {
            self.applyDeepLinkMetadataForRestore()
            self.onboardingVC.showLoading()
            Task { [weak self] in
                await self?.restoreCanonicalOnboarding()
            }
        } else {
            self.setInitialOnboardingContent()
            self.handle(deeplink: self.deepLink)
        }
    }

#if DEBUG
    /// A deterministic, local-only entry point for Product Design QA. It never creates a user,
    /// starts verification, uploads a photo, or changes Parse state.
    private func startOnboardingPreviewIfRequested() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let environmentVariant = ProcessInfo.processInfo.environment[
            "JIBBER_ONBOARDING_PREVIEW"
        ]
        guard (arguments.contains("-OnboardingPreview")
               || arguments.contains("OnboardingPreview")
               || environmentVariant?.isEmpty == false) else {
            return false
        }

        let requestedVariants = arguments + [environmentVariant].compactMap { $0 }
        let showsWelcomeInviteEntry = requestedVariants.contains("welcomeInvite")
            || requestedVariants.contains("inviteCode")
        let showsCapturedPhoto = requestedVariants.contains("capturedPhoto")
        let step = showsCapturedPhoto
            ? OnboardingStepID.faceCapture
            : OnboardingStepID.allCases.first {
                requestedVariants.contains($0.rawValue)
            } ?? .welcome

        let guide = SystemAvatar(
            givenName: "Maya",
            familyName: "",
            handle: "",
            phoneNumber: nil,
            image: UIImage(named: "OnboardingGuidePreview")
        )
        self.onboardingVC.setGuide(person: guide, displayName: guide.givenName)
        self.onboardingVC.preparePreview(
            step: step,
            showsWelcomeInviteEntry: showsWelcomeInviteEntry,
            showsCapturedPhoto: showsCapturedPhoto
        )
        return true
    }
#endif
    
    func handle(deeplink: DeepLinkable?) {
        guard let link = deeplink else { return }
        
        if let target = link.deepLinkTarget, target == .moment {
            self.presentMoment(with: link)
        } else {
            self.onboardingVC.reservationId = link.reservationId ?? ""
            self.onboardingVC.passId = link.passId ?? ""
            self.onboardingVC.momentId = ""
            if !self.onboardingVC.reservationId.isEmpty {
                // Resolve the contextual invitation before exposing the generic
                // Welcome choices. Resolution is non-claiming; the existing
                // invitation decision UI remains authoritative.
                self.onboardingVC.handle(
                    launchActivity: .reservation(
                        reservationId: self.onboardingVC.reservationId
                    )
                )
                return
            }
            if !self.onboardingVC.passId.isEmpty {
                self.onboardingVC.handle(
                    launchActivity: .pass(passId: self.onboardingVC.passId)
                )
                return
            }
            self.onboardingVC.updateUI()
        }
    }
    
    // MARK: - Onboarding Flow Logic

    private var shouldRestoreCanonicalOnboarding: Bool {
        guard self.onboardingVC.isCanonicalConversationEnabled,
              let user = User.current(),
              user.isAuthenticated else {
            return false
        }
        return user.status != .active
    }

    /// The authenticated session is authoritative on relaunch, but retain any
    /// incoming invitation/Moment fields so final routing does not discard them.
    private func applyDeepLinkMetadataForRestore() {
        guard let deepLink = self.deepLink else { return }
        if let reservationId = deepLink.reservationId, !reservationId.isEmpty {
            self.onboardingVC.reservationId = reservationId
        }
        if let passId = deepLink.passId, !passId.isEmpty {
            self.onboardingVC.passId = passId
        }
        if let momentId = deepLink.momentId, !momentId.isEmpty {
            self.onboardingVC.momentId = momentId
        }
    }

    @MainActor
    private func restoreCanonicalOnboarding() async {
        var didSynchronize = false
        do {
            try await self.syncCanonicalConversation()
            didSynchronize = true
        } catch {
            // The user profile still tells us which input is incomplete. Keep
            // onboarding usable, but never finalize or skip OTP from profile
            // state while a pending phone restart may exist only in session.
            self.isAwaitingAuthoritativeRestore = true
            self.queueCanonicalConversationSync()
        }

        await self.onboardingVC.hideLoading()

        guard didSynchronize else {
            self.onboardingVC.phoneVC.usesAuthenticatedRestart = true
            self.onboardingVC.switchTo(.phone(self.onboardingVC.phoneVC))
            return
        }

        await self.routeRestoredCanonicalSession()
    }

    private func routeRestoredCanonicalSession() async {

        if self.onboardingVC.canonicalSession?.completed == true,
           let user = User.current(),
           user.status != .active {
            // Refresh first. If transport fails, the authenticated completed
            // session is still authoritative: establish the matching in-memory
            // status so MainCoordinator cannot gate the recovered route back
            // into onboarding. The server already committed this transition.
            _ = try? await user.fetchInBackground()
            if user.status != .active {
                user.status = .active
            }
        }

        if self.onboardingVC.canonicalSession?.completed == true
            || User.current()?.status == .active {
            self.finishFlow(
                with: self.completionDeepLink(
                    conversationId: self.onboardingVC.canonicalSession?.conversationId
                )
            )
            return
        }

        if let nextContent = self.getRestoredCanonicalContent()
            ?? self.getNextIncompleteOnboardingContent() {
            // A verified Parse user cannot recover an old OTP. If a legacy
            // status still reports needsVerification, restart from phone input.
            if case .code = nextContent,
               self.onboardingVC.codeVC.phoneNumber == nil {
                self.onboardingVC.phoneVC.usesAuthenticatedRestart = true
                self.onboardingVC.switchTo(.phone(self.onboardingVC.phoneVC))
            } else {
                self.onboardingVC.switchTo(nextContent)
            }
        } else {
            self.goToNextContentOrFinish()
        }
    }

    /// The server session captures pending verification state that is
    /// intentionally not committed to `_User` until OTP succeeds. Prefer it
    /// over the durable profile when resuming after an app kill.
    private func getRestoredCanonicalContent() -> OnboardingContent? {
        guard let session = self.onboardingVC.canonicalSession,
              let reachedStep = session.reachedStep else { return nil }

        switch reachedStep {
        case .welcome, .phone:
            self.onboardingVC.phoneVC.usesAuthenticatedRestart = User.current() != nil
            return .phone(self.onboardingVC.phoneVC)
        case .verification:
            guard self.onboardingVC.codeVC.phoneNumber != nil else {
                self.onboardingVC.phoneVC.usesAuthenticatedRestart = true
                return .phone(self.onboardingVC.phoneVC)
            }
            self.onboardingVC.codeVC.prepareForEditing()
            return .code(self.onboardingVC.codeVC)
        case .name:
            return .name(self.onboardingVC.nameVC)
        case .faceCapture:
            return .photo(self.onboardingVC.photoVC)
        case .completed:
            return nil
        }
    }
    
    private func setInitialOnboardingContent() {
        let userStatus = User.current()?.status
        
        let initialContent: OnboardingContent
        switch userStatus {
        case .needsVerification, .inactive, .waitlist:
            if self.onboardingVC.isCanonicalConversationEnabled,
               User.current()?.isAuthenticated == true,
               let nextContent = self.getNextIncompleteOnboardingContent() {
                initialContent = nextContent
            } else {
                initialContent = .welcome(self.onboardingVC.welcomeVC)
            }
        case .none:
            initialContent = .welcome(self.onboardingVC.welcomeVC)
        case .active:
            if self.deepLink?.reservationId != nil {
                initialContent = .welcome(self.onboardingVC.welcomeVC)
            } else {
                self.finishFlow(with: nil)
                return
            }
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
            guard let moment = try? await Moment.getObject(with: deepLink?.momentId),
                  let momentId = moment.objectId else {
                return
            }

            _ = try? await moment.retrieveDataIfNeeded()
            self.onboardingVC.momentId = momentId
            self.onboardingVC.reservationId = ""
            self.onboardingVC.passId = ""
            let context = try? await GetAppClipShareContext(
                kind: .moment,
                id: momentId
            ).makeRequest(andUpdate: [], viewsToIgnore: [self.onboardingVC.view])
            if let authorId = moment.author?.objectId {
                self.onboardingVC.invitorId = authorId
                if let context {
                    await self.onboardingVC.applyShareContext(context)
                } else {
                    try? await self.onboardingVC.updateInvitor(userId: authorId)
                }
            }
            AnalyticsManager.shared.trackEvent(
                type: .appClipInvoked,
                properties: ["kind": "moment"]
            )
            AnalyticsManager.shared.trackEvent(
                type: .appClipPreviewViewed,
                properties: ["kind": "moment"]
            )
            
            await Task.sleep(seconds: 0.5)
            
            let coordinator = MomentCoordinator(moment: moment,
                                                router: self.router,
                                                deepLink: deepLink)
            self.addChildAndStart(coordinator, finishedHandler: { [unowned self] (_) in
                self.router.topmostViewController.dismiss(animated: true) {
                    self.onboardingVC.welcomeVC.mode = .momentInvitation
                    self.onboardingVC.switchTo(
                        .momentInvitation(self.onboardingVC.welcomeVC)
                    )
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
               let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
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

    func onboardingViewControllerDidAcceptMomentInvitation(
        _ controller: OnboardingViewController
    ) {
        AnalyticsManager.shared.trackEvent(
            type: .appClipOnboardingStarted,
            properties: ["kind": "moment"]
        )
        self.goToNextContentOrFinish()
    }

    func onboardingViewControllerDidDeferMomentInvitation(
        _ controller: OnboardingViewController
    ) {
        guard !controller.momentId.isEmpty else { return }
        var deepLink = DeepLinkObject(target: .moment)
        deepLink.momentId = controller.momentId
        self.presentMoment(with: deepLink)
    }

    func onboardingViewControllerDidResolveActiveInvitation(
        _ controller: OnboardingViewController,
        accepted: Bool
    ) {
        var deepLink = DeepLinkObject(target: .home)
        if accepted {
            deepLink.reservationId = controller.reservationId
            deepLink.reservationCreatorId = controller.invitorId
        }
        self.finishFlow(with: deepLink)
    }
    
    func onboardingViewController(_ controller: OnboardingViewController, didEnter phoneNumber: PhoneNumber) {
        let codeVC = self.onboardingVC.codeVC
        codeVC.phoneNumber = phoneNumber
        codeVC.prepareForEditing()
        if controller.isCanonicalConversationEnabled,
           User.current()?.isAuthenticated == true {
            controller.beginVerificationRestart()
        }
        self.onboardingVC.switchTo(.code(codeVC))
    }
    
    func onboardingViewControllerDidVerifyCode(_ controller: OnboardingViewController,
                                               andReturnCID cid: String?) {
        guard controller.isCanonicalConversationEnabled else {
            self.goToNextContentOrFinish()
            return
        }

        if let response = controller.codeVC.canonicalVerificationResponse {
            controller.applyCanonicalSession(response.session)
            if response.session.completed
                || (response.existingUser && User.current()?.status == .active) {
#if !APPCLIP
                User.clearOnboardingHandoff()
#endif
                self.finishFlow(
                    with: self.completionDeepLink(
                        conversationId: response.session.conversationId ?? cid
                    )
                )
                return
            }
        }

        // Verification itself succeeded. Transcript seeding is idempotent and
        // best effort, so it must never keep the user on the OTP screen.
        self.queueCanonicalConversationSync()
        self.goToNextContentOrFinish()
    }
    
    func onboardingViewController(_ controller: OnboardingViewController, didEnterName name: String) {
        Task { _ = await self.onboardingViewController(controller, didSubmitName: name) }
    }

    func onboardingViewController(
        _ controller: OnboardingViewController,
        didSubmitName name: String
    ) async -> Bool {
        controller.handleComposerRequestState(.loading)
        do {
            guard let user = User.current() else {
                throw ClientError.apiError(detail: "Your session is no longer available.")
            }
            user.formatName(from: name)
            try await user.saveLocalThenServer()
            controller.handleComposerRequestState(.complete)
            self.queueCanonicalConversationSync()
            self.goToNextContentOrFinish()
            return true
        } catch {
            controller.handleComposerRequestState(.error(error.localizedDescription))
            await ToastScheduler.shared.schedule(toastType: .error(error))
            return false
        }
    }
    
    func onboardingViewControllerDidTakePhoto(_ controller: OnboardingViewController) {
        // The photo has already been persisted by the capture controller.
        // Conversation sync cannot be allowed to strand its terminal `.finish`.
        self.queueCanonicalConversationSync()
        self.goToNextContentOrFinish()
    }

    /// Coalesces reached-step changes and retries the idempotent server sync
    /// without blocking an already-successful onboarding transition.
    @MainActor
    private func queueCanonicalConversationSync() {
        guard self.onboardingVC.isCanonicalConversationEnabled,
              User.current() != nil,
              !self.isFinishingCanonicalFlow else { return }

        self.canonicalSyncRequest += 1
        guard self.canonicalSyncTask == nil else { return }

        self.canonicalSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let retryDelays: [TimeInterval] = [0, 0.75, 2, 5, 12]

            while !Task.isCancelled {
                let request = self.canonicalSyncRequest
                var succeeded = false

                for delayInterval in retryDelays {
                    guard !Task.isCancelled else { break }
                    if delayInterval > 0 {
                        await Task.sleep(seconds: delayInterval)
                    }
                    do {
                        try await self.syncCanonicalConversation()
                        succeeded = true
                        break
                    } catch {
                        continue
                    }
                }

                if self.canonicalSyncRequest > request {
                    continue
                }
                if !succeeded {
                    // A later transition or authenticated relaunch will queue a
                    // fresh attempt. Authoritative profile state is preserved.
                }
                break
            }

            self.canonicalSyncTask = nil
        }
    }

    @MainActor
    private func syncCanonicalConversation() async throws {
        guard self.onboardingVC.isCanonicalConversationEnabled,
              User.current() != nil else { return }

        let response = try await SyncOnboardingConversationV1(
            locale: self.onboardingVC.messagingLocaleIdentifier
        ).makeRequest(andUpdate: [], viewsToIgnore: [self.onboardingVC.view])

        guard !Task.isCancelled, !self.isFinishingCanonicalFlow else { return }

        if let guideUserId = response.session.guideUserId,
           guideUserId != self.onboardingVC.invitorId {
            try? await self.onboardingVC.updateInvitor(userId: guideUserId)
        }
        self.onboardingVC.applyCanonicalSession(response.session)
        self.onboardingVC.reconcileConversation(response)

        if self.isAwaitingAuthoritativeRestore {
            self.isAwaitingAuthoritativeRestore = false
            await self.routeRestoredCanonicalSession()
        }
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
            self.isFinishingCanonicalFlow = true
            self.canonicalSyncTask?.cancel()
            self.canonicalSyncTask = nil
            self.onboardingVC.showLoading()
            
            do {
                if self.onboardingVC.isCanonicalConversationEnabled {
                    let response = try await FinalizeOnboardingV2(
                        locale: self.onboardingVC.messagingLocaleIdentifier
                    ).makeRequest(
                        andUpdate: [],
                        viewsToIgnore: [self.onboardingVC.view]
                    )
                    self.onboardingVC.applyCanonicalSession(response.session)
                    _ = try await user.fetchInBackground()
                } else {
                    try await FinalizeOnboarding(
                        reservationId: self.onboardingVC.reservationId,
                        passId: self.onboardingVC.passId,
                        momentId: self.onboardingVC.momentId
                    ).makeRequest(andUpdate: [], viewsToIgnore: [self.onboardingVC.view])
                }
            } catch {
                self.isFinishingCanonicalFlow = false
                await ToastScheduler.shared.schedule(toastType: .error(error))
                await self.onboardingVC.hideLoading()
                return
            }
            
            AnalyticsManager.shared.trackEvent(type: .finalizedOnboarding, properties: ["status": user.status?.rawValue ?? ""])
            let appClipKind: String?
            if !self.onboardingVC.momentId.isEmpty {
                appClipKind = "moment"
            } else if !self.onboardingVC.reservationId.isEmpty {
                appClipKind = "invite"
            } else {
                appClipKind = nil
            }
            if let appClipKind {
                AnalyticsManager.shared.trackEvent(
                    type: .appClipOnboardingCompleted,
                    properties: ["kind": appClipKind]
                )
                AnalyticsManager.shared.trackEvent(
                    type: .appClipConnectionCompleted,
                    properties: ["kind": appClipKind]
                )
            }
            await self.onboardingVC.hideLoading()

#if !APPCLIP
            // Normal full-app completion already has an in-memory route. The
            // persisted token/CID exist only as crash recovery and should not
            // reopen onboarding's conversation on a later unrelated launch.
            User.clearOnboardingHandoff()
#endif
            
            self.finishFlow(
                with: self.completionDeepLink(
                    conversationId: self.onboardingVC.canonicalSession?.conversationId
                )
            )
        }
    }

    private func completionDeepLink(conversationId: String?) -> DeepLinkObject {
        let canonicalConversationId = conversationId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasConversation = canonicalConversationId?.isEmpty == false
        var deepLink = DeepLinkObject(
            target: hasConversation ? .conversation : .home,
            preserving: self.deepLink
        )

        if !self.onboardingVC.reservationId.isEmpty {
            deepLink.reservationId = self.onboardingVC.reservationId
        }
        if !self.onboardingVC.passId.isEmpty {
            deepLink.passId = self.onboardingVC.passId
        }
        if !self.onboardingVC.momentId.isEmpty {
            deepLink.momentId = self.onboardingVC.momentId
            deepLink.reservationCreatorId = self.onboardingVC.invitorId
        }
        if let canonicalConversationId, !canonicalConversationId.isEmpty {
            deepLink.conversationId = canonicalConversationId
        }
        return deepLink
    }
}

// MARK: - Launch Activity Handling

extension OnboardingCoordinator: LaunchActivityHandler {
    
    func handle(launchActivity: LaunchActivity) {
        self.onboardingVC.handle(launchActivity: launchActivity)
    }
}
