//
//  OnboardingViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 1/14/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Combine
import Foundation
import ParseCore
import Lottie
import Intents
import Localization
import PhoneNumberKit
import Transitions

@MainActor
protocol OnboardingViewControllerDelegate: AnyObject {
    func onboardingViewControllerDidStartOnboarding(_ controller: OnboardingViewController)
    func onboardingViewControllerDidSelectRSVP(_ controller: OnboardingViewController)
    func onboardingViewControllerDidAcceptMomentInvitation(_ controller: OnboardingViewController)
    func onboardingViewControllerDidDeferMomentInvitation(_ controller: OnboardingViewController)
    func onboardingViewControllerDidResolveActiveInvitation(
        _ controller: OnboardingViewController,
        accepted: Bool
    )
    func onboardingViewController(_ controller: OnboardingViewController, didEnter phoneNumber: PhoneNumber)
    func onboardingViewControllerDidVerifyCode(_ controller: OnboardingViewController,
                                               andReturnCID conversationId: String?)
    func onboardingViewController(_ controller: OnboardingViewController, didEnterName name: String)
    func onboardingViewController(
        _ controller: OnboardingViewController,
        didSubmitName name: String
    ) async -> Bool
    func onboardingViewControllerDidTakePhoto(_ controller: OnboardingViewController)
}

extension OnboardingViewControllerDelegate {
    func onboardingViewController(
        _ controller: OnboardingViewController,
        didSubmitName name: String
    ) async -> Bool {
        self.onboardingViewController(controller, didEnterName: name)
        return true
    }
}

class OnboardingViewController: SwitchableContentViewController<OnboardingContent>,
                                TransitionableViewController {

    // MARK: - Transitionable

    var presentationType: TransitionType {
        return .fadeOutIn
    }

    var dismissalType: TransitionType {
        return self.presentationType
    }

    func getFromVCPresentationType(for toVCPresentationType: TransitionType) -> TransitionType {
        return toVCPresentationType
    }

    func getToVCDismissalType(for fromVCDismissalType: TransitionType) -> TransitionType {
        return fromVCDismissalType
    }

    // MARK: - Views

    lazy var welcomeVC = WelcomeViewController()
    lazy var phoneVC = PhoneViewController()
    lazy var codeVC = CodeViewController()
    lazy var nameVC = NameViewController()
    lazy var photoVC = ProfilePhotoCaptureViewController()

    let loadingBlur = BlurView()
    let loadingAnimationView = LottieAnimationView()

    unowned let delegate: OnboardingViewControllerDelegate
    private var messaging: OnboardingMessaging
    private var highestReachedStep: OnboardingStepID = .welcome
    private var isViewingCompletedVerification = false
    private var isResolvingManualInvitation = false
    private var isSubmittingName = false
    private var hasManualInvitationContext = false
    private var guideBeforeManualInvitation: PersonType?
    private var guideNameBeforeManualInvitation: String?
    private var guideUserIDBeforeManualInvitation: String?
    private var wasAIGuideBeforeManualInvitation = false
    private var isAIGuide = false
#if DEBUG
    private var forcesCanonicalConversationPreview = false
#endif

    private(set) var canonicalSession: OnboardingConversationSession?

    var isCanonicalConversationEnabled: Bool {
#if DEBUG
        if self.forcesCanonicalConversationPreview { return true }
#endif
        return PFConfig.current().isConversationOnboardingEnabled
    }

    var entryContext: OnboardingEntryContext {
        OnboardingEntryContext(
            reservationId: self.reservationId,
            passId: self.passId,
            momentId: self.momentId
        )
    }

    var messagingLocaleIdentifier: String {
        self.messaging.localeIdentifier
    }

    var reservationId: String = "" {
        didSet {
            self.codeVC.reservationId = self.reservationId
        }
    }

    var passId: String = "" {
        didSet {
            self.codeVC.passId = self.passId
        }
    }

    var momentId: String = "" {
        didSet {
            self.codeVC.momentId = self.momentId
        }
    }
    var inviteMessage: String?

    var invitor: User?
    var invitorId: String?
    var invitorDisplayName: String?

    init(with delegate: OnboardingViewControllerDelegate) {
        self.delegate = delegate
        self.messaging = OnboardingMessagingRepository.shared.sessionSnapshot()
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        self.loadingAnimationView.load(animation: .loading)
        self.loadingAnimationView.loopMode = .loop
        self.loadingBlur.contentView.addSubview(self.loadingAnimationView)
        
        Task {
            guard let guideUserId = self.messaging.guideUserId
                    ?? PFConfig.current().adminUserId else { return }

            do {
                guard self.invitor.isNil,
                      self.reservationId.isEmpty,
                      self.passId.isEmpty,
                      self.momentId.isEmpty else { return }
                let user = try await User.getObject(with: guideUserId)
                guard self.invitor.isNil,
                      self.reservationId.isEmpty,
                      self.passId.isEmpty,
                      self.momentId.isEmpty,
                      !self.isResolvingManualInvitation,
                      !self.hasManualInvitationContext else { return }
                self.applyInvitor(user, userId: guideUserId)
            } catch {
                return
            }
        }

        self.welcomeVC.onDidComplete = { [unowned self] result in
            switch result {
            case .success(let selection):
                switch selection {
                case .waitlist:
                    self.clearManualInvitationContextIfAllowed()
                    self.delegate.onboardingViewControllerDidStartOnboarding(self)
                case .rsvp:
                    self.delegate.onboardingViewControllerDidSelectRSVP(self)
                case .acceptInvite:
                    self.respondToInvitation(with: .accepted)
                case .declineInvite:
                    self.respondToInvitation(with: .declined)
                case .acceptMomentInvite:
                    self.delegate.onboardingViewControllerDidAcceptMomentInvitation(self)
                case .deferMomentInvite:
                    self.delegate.onboardingViewControllerDidDeferMomentInvitation(self)
                }
            case .failure:
                break
            }
        }
        self.welcomeVC.usesCanonicalEntryChoices = self.isCanonicalConversationEnabled
        self.welcomeVC.onCanonicalEntryStateChanged = { [weak self] _ in
            guard let self else { return }
            self.updateUI(animateTyping: false)
        }
        self.welcomeVC.onInviteCodeTextChanged = { [weak self] in
            self?.refreshComposerSubmissionState()
        }
        self.welcomeVC.onResolveInviteCode = { [weak self] code in
            Task { [weak self] in
                _ = await self?.resolveManualInvitation(code: code)
            }
        }

        self.phoneVC.onDidComplete = { [unowned self] result in
            switch result {
            case .success(let phone):
                self.delegate.onboardingViewController(self, didEnter: phone)
            case .failure(let error):
                Task {
                    await ToastScheduler.shared.schedule(toastType: .error(error))
                }
            }
        }

        self.codeVC.onDidComplete = { [unowned self] result in
            switch result {
            case .success(let conversationId):
                self.delegate.onboardingViewControllerDidVerifyCode(self,
                                                                    andReturnCID: conversationId)
            case .failure(let error):
                Task {
                    await ToastScheduler.shared.schedule(toastType: .error(error))
                }
            }
        }

        self.nameVC.onDidComplete = { [unowned self] result in
            switch result {
            case .success(let name):
                self.delegate.onboardingViewController(self, didEnterName: name)
            case .failure(_):
                break
            }
        }
        
        self.nameVC.$state
            .mainSink { [unowned self] _ in
                self.updateUI()
            }.store(in: &self.cancellables)

        self.phoneVC.textField.addTarget(
            self,
            action: #selector(self.embeddedInputDidChange),
            for: .editingChanged
        )
        self.codeVC.textField.addTarget(
            self,
            action: #selector(self.embeddedInputDidChange),
            for: .editingChanged
        )

        self.photoVC.onDidComplete = { [unowned self] result in
            switch result {
            case .success:
                self.delegate.onboardingViewControllerDidTakePhoto(self)
            case .failure(_):
                break
            }
        }

        self.photoVC.$currentState
            .mainSink { [weak self] _ in
                guard let self,
                      self.getCurrentStepID() == .faceCapture else { return }
                self.updateUI(animateTyping: false)
            }.store(in: &self.cancellables)

        self.photoVC.$contextText
            .removeDuplicates()
            .mainSink { [weak self] _ in
                guard let self,
                      self.getCurrentStepID() == .faceCapture else { return }
                self.updateUI(animateTyping: false)
            }.store(in: &self.cancellables)

        self.configureCanonicalVerification()
        self.configureCanonicalInputPresentation()
        self.configureEmbeddedRequestState()
        self.applyServerDrivenControlCopy()
    }

    @objc private func embeddedInputDidChange() {
        self.refreshComposerSubmissionState()
    }

    private func configureCanonicalVerification() {
        self.codeVC.usesCanonicalConversation = self.isCanonicalConversationEnabled
        self.codeVC.contextProvider = { [weak self] in
            self?.entryContext ?? OnboardingEntryContext()
        }
        self.codeVC.localeProvider = { [weak self] in
            self?.messagingLocaleIdentifier
        }
    }

    private func configureCanonicalInputPresentation() {
        // The shared conversation shell is the sole visual composer in both
        // endpoint modes. The feature flag selects server behavior, not a
        // second keyboard toolbar or photo action implementation.
        self.phoneVC.usesEmbeddedComposer = true
        self.codeVC.usesEmbeddedComposer = true
        self.nameVC.usesEmbeddedComposer = true
        self.photoVC.usesEmbeddedComposer = true
    }

    private func configureEmbeddedRequestState() {
        let updateComposer: (EventStatus) -> Void = { [weak self] status in
            self?.handleComposerRequestState(status)
        }
        self.phoneVC.onRequestStateChanged = updateComposer
        self.codeVC.onRequestStateChanged = updateComposer
        self.photoVC.onRequestStateChanged = updateComposer
    }

    private func applyServerDrivenControlCopy() {
        self.welcomeVC.setCanonicalChoiceTitles(
            account: self.messaging.text(for: .welcomeAccountChoice),
            invite: self.messaging.text(for: .welcomeInviteChoice)
        )
        self.phoneVC.setActionTitle(self.localizedMessage(for: .phoneAction))
        self.codeVC.setActionTitle(self.localizedMessage(for: .codeAction))
        self.nameVC.setActionTitle(self.localizedMessage(for: .nameAction))

        self.photoVC.captureButtonTitle = self.messaging.text(for: .photoCapture)
        self.photoVC.reviewButtonTitle = self.messaging.text(for: .photoReview)
        self.photoVC.noFaceMessage = self.messaging.text(for: .photoNoFace)
        self.photoVC.notSmilingMessage = self.messaging.text(for: .photoNotSmiling)
        self.photoVC.uploadErrorMessage = self.messaging.text(for: .photoUploadError)
        self.photoVC.scanningMessage = self.messaging.text(for: .photoContext)
        self.photoVC.cameraDeniedMessage = self.messaging.text(for: .photoCameraDenied)
        self.photoVC.cameraRestrictedMessage = self.messaging.text(for: .photoCameraRestricted)
        self.photoVC.cameraStartErrorMessage = self.messaging.text(for: .photoCameraStartError)
        self.photoVC.openSettingsButtonTitle = self.messaging.text(for: .photoOpenSettings)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.loadingBlur.expandToSuperviewSize()

        self.loadingAnimationView.size = CGSize(width: 18, height: 18)
        self.loadingAnimationView.centerOnXAndY()
    }

    override func updateUI(animateTyping: Bool = true) {
#if DEBUG
        // Design QA launches must settle on an exact Time Machine item. Animated
        // focus briefly scales the next card above 1x, which is useful in motion
        // but produces a misleading, cropped still image during automation.
        if self.forcesCanonicalConversationPreview {
            super.updateUI(animateTyping: false)
            return
        }
#endif
        super.updateUI(animateTyping: animateTyping)
    }

    // MARK: - SwitchableContentViewController Overrides

    override func willUpdateContent() {
        super.willUpdateContent()

        // All canonical inputs, including the two Welcome choices, are hosted
        // inside the same production-derived composer bubble.
        self.currentContent?.viewController.view.isHidden = false

        let step = self.getCurrentStepID()
        if step.timelineOrdinal > self.highestReachedStep.timelineOrdinal {
            self.highestReachedStep = step
        }
        self.currentContent?.viewController.view.isUserInteractionEnabled =
            !self.isViewingCompletedVerification
    }

    override func didSelectTimelineStep(_ step: OnboardingStepID) {
        guard self.isCanonicalConversationEnabled else { return }
        guard step.timelineOrdinal <= self.highestReachedStep.timelineOrdinal else { return }
        self.presentTimelineStep(step)
    }

    override func didSelectPrimaryAction() {
        Task { _ = await self.commitPrimaryAction() }
    }

    override func commitPrimaryAction() async -> Bool {
        guard let content = self.currentContent else { return false }

#if DEBUG
        if self.forcesCanonicalConversationPreview {
            self.didSelectPreviewPrimaryAction(for: content)
            return true
        }
#endif

        switch content {
        case .phone(let controller):
            return await controller.submitPhoneNumber()
        case .code(let controller):
            return await controller.submitCode()
        case .name(let controller):
            guard !self.isSubmittingName,
                  let name = controller.textField.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  controller.isSubmissionValid(name) else { return false }
            self.isSubmittingName = true
            defer { self.isSubmittingName = false }
            return await self.delegate.onboardingViewController(
                self,
                didSubmitName: name
            )
        case .photo(let controller):
            return await controller.submitCapturedPhotoAndWait()
        case .welcome(let controller):
            if controller.mode == .pass {
                self.delegate.onboardingViewControllerDidStartOnboarding(self)
                return true
            } else {
                return await self.resolveManualInvitation(
                    code: controller.enteredInviteCode
                )
            }
        case .invitation, .momentInvitation:
            return false
        }
    }

#if DEBUG
    /// Keeps the interactive Product Design fixture useful without allowing it
    /// to invoke verification, Parse saves, uploads, or finalization callbacks.
    private func didSelectPreviewPrimaryAction(for content: OnboardingContent) {
        switch content {
        case .welcome:
            self.presentTimelineStep(.phone)
        case .phone:
            self.presentTimelineStep(.verification)
        case .code:
            self.presentTimelineStep(.name)
        case .name:
            self.presentTimelineStep(.faceCapture)
        case .photo(let controller):
            controller.didTapPrimaryAction()
        case .invitation, .momentInvitation:
            break
        }
    }
#endif

    private func presentTimelineStep(_ step: OnboardingStepID) {
        self.isViewingCompletedVerification = false
        switch step {
        case .welcome:
            self.welcomeVC.setCanonicalEntryLocked(self.canonicalSession != nil)
            if self.canonicalSession != nil {
                self.welcomeVC.mode = .standard
                self.switchTo(.welcome(self.welcomeVC))
            } else if !self.momentId.isEmpty {
                self.welcomeVC.mode = .momentInvitation
                self.switchTo(.momentInvitation(self.welcomeVC))
            } else if !self.passId.isEmpty {
                self.welcomeVC.mode = .pass
                self.switchTo(.welcome(self.welcomeVC))
            } else if self.reservationId.isEmpty || self.hasManualInvitationContext {
                self.welcomeVC.mode = .standard
                self.welcomeVC.showChoices()
                self.switchTo(.welcome(self.welcomeVC))
            } else {
                self.welcomeVC.mode = .invitation
                self.switchTo(.invitation(self.welcomeVC))
            }
        case .phone:
            self.hydrateCompletedProfileFieldsIfNeeded()
            self.phoneVC.usesAuthenticatedRestart = self.isCanonicalConversationEnabled
                && User.current() != nil
            self.phoneVC.setEmbeddedComposerReviewing(false)
            self.switchTo(.phone(self.phoneVC))
        case .verification:
            if step.timelineOrdinal < self.highestReachedStep.timelineOrdinal {
                self.isViewingCompletedVerification = true
                self.codeVC.prepareForReview()
            } else {
                self.codeVC.prepareForEditing()
            }
            self.switchTo(.code(self.codeVC))
        case .name:
            self.hydrateCompletedProfileFieldsIfNeeded()
            self.nameVC.setEmbeddedComposerReviewing(false)
            self.switchTo(.name(self.nameVC))
        case .faceCapture:
            self.switchTo(.photo(self.photoVC))
        case .completed:
            break
        }
    }

    override func getMessage() -> Localized? {
        guard let content = self.currentContent else { return nil }
        switch content {
        case .welcome:
            if !self.momentId.isEmpty {
                return self.localizedMessage(for: .welcomeMomentInvitation)
            }
            if self.welcomeVC.mode == .pass || !self.reservationId.isEmpty {
                return self.invitationWelcomeMessage()
            }
            if self.hasManualInvitationContext {
                return self.invitationWelcomeMessage()
            }
            return self.localizedMessage(for: .welcomeStandard)
        case .invitation:
            return self.invitationWelcomeMessage()
        case .momentInvitation:
            return self.localizedMessage(for: .welcomeMomentInvitation)
        case .phone:
            let hasInvitationContext = !self.reservationId.isEmpty
                || !self.passId.isEmpty
                || !self.momentId.isEmpty
            return self.localizedMessage(
                for: hasInvitationContext ? .phoneInvited : .phoneDefault
            )
        case .code:
            return self.localizedMessage(for: .codeBody)
        case .name(let controller):
            switch controller.state {
            case .noName:
                return self.localizedMessage(for: .nameFirst)
            case .givenNameValid:
                return self.localizedMessage(for: .nameLast)
            case .validFullName:
                return self.localizedMessage(for: .nameConfirm)
            }
        case .photo:
            return self.localizedMessage(for: .photoBody)
        }
    }

    override func getCurrentStepID() -> OnboardingStepID {
        guard let content = self.currentContent else { return .welcome }
        switch content {
        case .welcome, .invitation, .momentInvitation:
            return .welcome
        case .phone:
            return .phone
        case .code:
            return .verification
        case .name:
            return .name
        case .photo:
            return .faceCapture
        }
    }

    override func getComposerMode() -> ConversationComposerMode {
        if case .welcome(let controller) = self.currentContent,
           self.isCanonicalConversationEnabled,
           controller.mode == .standard {
            if controller.isCanonicalEntryLocked {
                return .action
            }
            switch controller.canonicalEntryState {
            case .choices:
                return .welcomeChoices
            case .inviteCode, .resolvingInvite:
                return .inviteCode
            }
        }

        switch self.messaging.inputKind(for: self.getCurrentStepID()) {
        case .action:
            return .action
        case .phone:
            return .phone
        case .verificationCode:
            return .verificationCode
        case .name:
            return .name
        case .faceCapture:
            return .faceCapture
        case .review:
            // Review remains decodable for pinned legacy messaging documents,
            // but the canonical five-step UI never renders a Review/Edit state.
            return .action
        case .chat:
            return .chat
        case .none:
            return .action
        }
    }

    override func getMessagingRevision() -> Int {
        // A session is copy-version locked on the server. Reusing that
        // revision keeps temporary prompt IDs identical to persisted messages
        // even when Parse Config advances while onboarding is in progress.
        self.canonicalSession?.messagingRevision ?? self.messaging.revision
    }

    override func getProgress() -> CGFloat {
        CGFloat(self.getCurrentStepID().timelineOrdinal + 1)
    }

    override func getStepTitle() -> String {
        let step = self.getCurrentStepID()
        return "\(step.timelineOrdinal + 1). \(self.messaging.title(for: step))"
    }

    override func getContextIndicatorText() -> String? {
        guard let content = self.currentContent else { return nil }
        switch content {
        case .welcome(let controller):
            if controller.mode == .pass { return nil }
            return controller.canonicalEntryState == .choices
                ? nil
                : self.messaging.text(for: .inviteContext)
        case .invitation, .momentInvitation:
            return nil
        case .phone:
            return self.messaging.inputContext(
                for: .phone,
                replacements: self.messageReplacements
            )
        case .code:
            let base = self.messaging.inputContext(
                for: .verification,
                replacements: self.messageReplacements
            )
            return base.replacingOccurrences(
                of: "%@",
                with: self.maskedVerificationDestination
            )
        case .name:
            return self.messaging.inputContext(
                for: .name,
                replacements: self.messageReplacements
            )
        case .photo(let controller):
            let context = controller.contextText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return context.isEmpty
                ? self.messaging.inputContext(
                    for: .faceCapture,
                    replacements: self.messageReplacements
                )
                : context
        }
    }

    override func getSwipeUpAccessibilityName() -> String? {
        guard self.shouldEnablePrimaryAction(), let content = self.currentContent else {
            return nil
        }
        switch content {
        case .welcome:
            return self.welcomeVC.mode == .pass
                ? "Continue"
                : "Submit invite code"
        case .phone:
            return "Submit phone number"
        case .code:
            return "Verify code"
        case .name:
            return "Submit name"
        case .photo:
            return "Use photo"
        case .invitation, .momentInvitation:
            return nil
        }
    }

    override func getSwipeDownAccessibilityName() -> String? {
        self.shouldEnableSwipeDownAction() ? "Back to options" : nil
    }

    override func getComposerHeight() -> CGFloat {
        guard let content = self.currentContent else { return 144 }
        switch content {
        case .welcome where self.isCanonicalConversationEnabled:
            if self.welcomeVC.mode == .pass
                || self.welcomeVC.isCanonicalEntryLocked { return 84 }
            switch self.welcomeVC.canonicalEntryState {
            case .choices:
                return 144
            case .inviteCode, .resolvingInvite:
                return 112
            }
        case .welcome, .invitation, .momentInvitation:
            return 156
        case .phone, .code, .name:
            return 112
        case .photo:
            return 420
        }
    }

    override func shouldEnablePrimaryAction() -> Bool {
        guard let content = self.currentContent else { return false }
        switch content {
        case .welcome(let controller):
            if controller.isCanonicalEntryLocked { return false }
            if controller.mode == .pass { return true }
            return controller.canonicalEntryState == .inviteCode
                && !controller.enteredInviteCode.isEmpty
        case .invitation, .momentInvitation:
            return false
        case .phone(let controller):
            return controller.validate(text: controller.textField.text ?? "")
        case .code(let controller):
            return !self.isViewingCompletedVerification
                && controller.validate(text: controller.textField.text ?? "")
        case .name(let controller):
            return controller.isSubmissionValid(controller.textField.text ?? "")
        case .photo(let controller):
            return controller.canSubmitCapturedPhoto
        }
    }

    override func shouldEnableSwipeDownAction() -> Bool {
        guard case .welcome(let controller) = self.currentContent else { return false }
        return !controller.isCanonicalEntryLocked
            && controller.canonicalEntryState == .inviteCode
    }

    override func didSelectComposerSwipeDown() {
        guard case .welcome(let controller) = self.currentContent,
              controller.canonicalEntryState == .inviteCode else { return }
        _ = controller.returnToChoices()
    }

    private var maskedVerificationDestination: String {
        let source: String
        if let phone = self.codeVC.phoneNumber {
            source = PhoneKit.shared.format(phone, toType: .e164)
        } else {
            source = self.phoneVC.textField.text ?? ""
        }
        let suffix = source.filter(\.isNumber).suffix(4)
        return suffix.count == 4 ? "••• ••• \(suffix)" : "••• ••• ••••"
    }

    private func invitationWelcomeMessage() -> Localized {
        if let inviteMessage = self.inviteMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !inviteMessage.isEmpty {
            let base = self.messaging.text(
                for: .welcomeInvitation,
                replacements: self.messageReplacements
            )
            return LocalizedString(
                id: "",
                arguments: [],
                default: "\(base)\n\n“\(inviteMessage)”"
            )
        }
        return self.localizedMessage(for: .welcomeInvitation)
    }

    @discardableResult
    private func resolveManualInvitation(code: String) async -> Bool {
        guard self.isCanonicalConversationEnabled,
              self.canonicalSession == nil,
              !self.isResolvingManualInvitation,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if !self.hasManualInvitationContext {
            self.guideBeforeManualInvitation = self.guidePerson
            self.guideNameBeforeManualInvitation = self.guideDisplayName
            self.guideUserIDBeforeManualInvitation = self.timelineStore.guideUserId
            self.wasAIGuideBeforeManualInvitation = self.isAIGuide
        }

        self.welcomeVC.setResolvingInviteCode(true)
        self.isResolvingManualInvitation = true
        self.handleComposerRequestState(.loading)
        do {
            let response = try await ResolveInvitationCodeV1(
                code: code
            ).makeRequest(andUpdate: [], viewsToIgnore: [self.view])
            try Task.checkCancellation()

            // Authentication may have completed through another path while
            // the unauthenticated resolver was in flight. Never let its older
            // response replace the session's immutable guide context.
            guard await self.applyResolvedManualInvitation(response) else {
                self.isResolvingManualInvitation = false
                self.handleComposerRequestState(.complete)
                return false
            }

            self.isResolvingManualInvitation = false
            self.handleComposerRequestState(.complete)
            self.presentTimelineStep(.phone)
            return true
        } catch {
            self.isResolvingManualInvitation = false
            self.welcomeVC.setResolvingInviteCode(false)
            self.handleComposerRequestState(.error(error.localizedDescription))
            await ToastScheduler.shared.schedule(
                toastType: .error(self.displayError(forInvitationResolution: error))
            )
            return false
        }
    }

    @MainActor
    private func applyResolvedManualInvitation(
        _ response: OnboardingInvitationResolutionResponse
    ) async -> Bool {
        guard self.canonicalSession == nil else { return false }
        var image: UIImage?
        if let url = response.guideAvatarURL,
           let (data, _) = try? await URLSession.shared.data(from: url) {
            image = UIImage(data: data)
        }

        guard self.canonicalSession == nil else { return false }

        let displayName = response.guideDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = displayName.split(separator: " ").first.map(String.init)
            ?? displayName
        let avatar = SystemAvatar(
            givenName: firstName,
            familyName: "",
            handle: "",
            phoneNumber: nil,
            image: image
        )

        self.hasManualInvitationContext = true
        self.reservationId = response.reservationId
        self.passId = ""
        self.momentId = ""
        self.inviteMessage = response.invitationMessage
        self.invitor = nil
        self.invitorId = response.guideUserId
        self.invitorDisplayName = displayName
        self.isAIGuide = false
        self.setGuide(
            person: avatar,
            displayName: displayName,
            guideUserId: response.guideUserId
        )
        return true
    }

    private func clearManualInvitationContextIfAllowed() {
        guard self.canonicalSession == nil,
              self.hasManualInvitationContext else { return }

        let shouldReloadConfiguredGuide = self.guideBeforeManualInvitation == nil
        self.hasManualInvitationContext = false
        self.welcomeVC.showChoices(clearInviteCode: true)
        self.reservationId = ""
        self.passId = ""
        self.momentId = ""
        self.inviteMessage = nil
        self.invitor = nil
        self.invitorId = nil
        self.invitorDisplayName = self.guideNameBeforeManualInvitation
        self.isAIGuide = self.wasAIGuideBeforeManualInvitation
        self.setGuide(
            person: self.guideBeforeManualInvitation,
            displayName: self.guideNameBeforeManualInvitation,
            guideUserId: self.guideUserIDBeforeManualInvitation
                ?? self.messaging.guideUserId
        )
        self.guideBeforeManualInvitation = nil
        self.guideNameBeforeManualInvitation = nil
        self.guideUserIDBeforeManualInvitation = nil
        if shouldReloadConfiguredGuide,
           let configuredGuideID = self.messaging.guideUserId
                ?? PFConfig.current().adminUserId {
            Task { [weak self] in
                try? await self?.updateInvitor(userId: configuredGuideID)
            }
        }
    }

    private func displayError(forInvitationResolution error: Error) -> NSError {
        let token = error.localizedDescription
        let message: String
        switch token {
        case let value where value.contains("invitation.claimed"):
            message = "That invite has already been claimed."
        case let value where value.contains("invitation.declined"):
            message = "That invite has been declined."
        case let value where value.contains("invitation.expired"):
            message = "That invite has expired."
        case let value where value.contains("invitation.revoked"):
            message = "That invite was revoked."
        case let value where value.contains("invitation.self"):
            message = "You can’t use your own invite."
        case let value where value.contains("invitation.context_conflict"):
            message = "This onboarding session is already connected to another guide."
        case let value where value.contains("invitation.rate_limited"):
            message = "Too many attempts. Wait a moment and try again."
        case let value where value.contains("invitation.transient"):
            message = "We couldn’t check that invite right now. Try again."
        default:
            message = "We couldn’t find that invite. Check the code or link and try again."
        }
        return NSError(
            domain: "com.jibber.onboarding.invitation-resolution",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    func applyCanonicalSession(_ session: OnboardingConversationSession) {
        self.canonicalSession = session
        self.welcomeVC.setCanonicalEntryLocked(true)
        if let revision = session.messagingRevision {
            let repository = OnboardingMessagingRepository.shared
            let lockedMessaging = session.messagingDocumentJSON.flatMap {
                repository.sessionSnapshot(
                    documentJSON: $0,
                    expectedRevision: revision
                )
            } ?? repository.sessionSnapshot(forRevision: revision)
            if let lockedMessaging {
                self.messaging = lockedMessaging
                self.applyServerDrivenControlCopy()
            }
        }
        self.isAIGuide = session.guideSource == .maya
            || session.guideSource == .configuredAgent
        if let reachedStep = session.reachedStep {
            // The server derives this from authoritative profile/session state.
            // A successful edit can intentionally lower it after invalidating
            // dependent name/photo steps, so this cannot be max-only.
            self.highestReachedStep = reachedStep
        }
        if let conversationId = session.conversationId, !conversationId.isEmpty {
            User.storeOnboardingConversationId(conversationId)
        }
        if let pendingPhoneNumber = session.pendingPhoneNumber,
           let parsedPendingPhone = pendingPhoneNumber.parsePhoneNumber(
                for: PhoneKit.defaultRegion
           ) {
            self.codeVC.phoneNumber = parsedPendingPhone
            self.phoneVC.textField.text = pendingPhoneNumber
            self.phoneVC.textField.sendActions(for: .editingChanged)
        } else {
            self.hydrateVerifiedPhoneIfNeeded(for: self.codeVC)
        }
        self.hydrateCompletedProfileFieldsIfNeeded()
        self.setGuide(
            person: self.invitor ?? self.guidePerson,
            displayName: self.invitorDisplayName,
            guideUserId: session.guideUserId,
            conversationId: session.conversationId,
            messagingRevision: session.messagingRevision
        )
    }

    private func hydrateVerifiedPhoneIfNeeded(for controller: CodeViewController) {
        guard controller.phoneNumber == nil,
              let phoneNumber = User.current()?.phoneNumber,
              let parsedPhoneNumber = phoneNumber.parsePhoneNumber(
                for: PhoneKit.defaultRegion
              ) else { return }
        controller.phoneNumber = parsedPhoneNumber
    }

    /// Fresh controllers have no drafts after an app kill. Hydrate completed,
    /// non-sensitive fields for Review without overwriting an in-session draft.
    private func hydrateCompletedProfileFieldsIfNeeded() {
        guard let user = User.current() else { return }

        if self.phoneVC.textField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let phoneNumber = user.phoneNumber,
           !phoneNumber.isEmpty {
            self.phoneVC.textField.text = phoneNumber
            self.phoneVC.textField.sendActions(for: .editingChanged)
        }

        let currentName = self.nameVC.textField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let savedName = user.fullName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if currentName?.isEmpty != false,
           savedName.isValidFullName {
            self.nameVC.textField.text = savedName
            self.nameVC.textField.sendActions(for: .editingChanged)
        }
    }

    /// A restart keeps the previously verified profile durable until the new
    /// OTP succeeds, but the visible navigation context must remain at the
    /// pending verification step in the meantime.
    func beginVerificationRestart() {
        self.highestReachedStep = .verification
        self.isViewingCompletedVerification = false
        self.updateUI(animateTyping: false)
    }

#if DEBUG
    /// Deterministic Product Design fixture that exercises the same shared timeline,
    /// message cell, header, and composer as the live server-backed flow.
    func preparePreview(
        step: OnboardingStepID,
        showsWelcomeInviteEntry: Bool = false,
        showsCapturedPhoto: Bool = false
    ) {
        self.forcesCanonicalConversationPreview = true
        self.welcomeVC.usesCanonicalEntryChoices = true
        self.photoVC.usesLocalPreviewFixture = true
        self.configureCanonicalVerification()
        self.configureCanonicalInputPresentation()
        self.applyServerDrivenControlCopy()
        self.isAIGuide = true
        if step.timelineOrdinal >= OnboardingStepID.verification.timelineOrdinal {
            self.phoneVC.textField.text = "(201) 555-0123"
        }
        let seeded: [(OnboardingStepID, OnboardingMessageKey)] = [
            (.welcome, .welcomeStandard),
            (.phone, .phoneDefault),
            (.verification, .codeBody),
            (.name, .nameFirst),
            (.faceCapture, .photoBody)
        ]
        for (seededStep, key) in seeded
            where seededStep.timelineOrdinal <= step.timelineOrdinal {
            self.timelineStore.upsertLocalPrompt(
                step: seededStep,
                text: self.messaging.text(for: key, replacements: self.messageReplacements),
                revision: self.messaging.revision
            )
        }
        self.highestReachedStep = step
        self.presentTimelineStep(step)
        if step == .welcome, showsWelcomeInviteEntry {
            self.welcomeVC.showInviteCodeEntry()
        }
        if step == .faceCapture, showsCapturedPhoto {
            self.photoVC.prepareCapturedPhotoPreview()
        }
        self.updateUI(animateTyping: false)
    }
#endif

    private var messageReplacements: [OnboardingMessageToken: String] {
        let inviterName = self.invitorDisplayName?.capitalized
            ?? self.invitor?.givenName.capitalized
            ?? self.guideDisplayName.capitalized
        let enteredName = self.nameVC.textField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = enteredName?.isEmpty == false
            ? enteredName!
            : (User.current()?.fullName ?? "")
        let firstName = fullName.split(separator: " ").first.map(String.init)
            ?? User.current()?.givenName
            ?? "there"

        return [
            .inviterName: inviterName,
            .fullName: fullName,
            .firstName: firstName
        ]
    }

    private func localizedMessage(for key: OnboardingMessageKey) -> Localized {
        return LocalizedString(
            id: "",
            arguments: [],
            default: self.messaging.text(for: key, replacements: self.messageReplacements)
        )
    }

    func handle(launchActivity: LaunchActivity) {

        switch launchActivity {
        case .onboarding(let phoneNumber):
            self.switchTo(.phone(self.phoneVC))

            delay(0.25) { [unowned self] in
                self.phoneVC.textField.text = phoneNumber
                self.phoneVC.didTapButton()
            }
        case .reservation(let reservationId):
            self.showLoading()
            Task {
                do {
                    let reservation = try await Reservation.getObject(with: reservationId)
                    let context = try? await GetAppClipShareContext(
                        kind: .invite,
                        id: reservationId
                    ).makeRequest(andUpdate: [], viewsToIgnore: [self.view])
                    guard let from = reservation.createdBy?.objectId else {
                        throw ClientError.message(detail: "That invite is no longer available.")
                    }
                    let isClaimedByCurrentUser = reservation.isClaimed
                        && reservation.user?.objectId == User.current()?.objectId

                    if context?["available"] as? Bool == false,
                       !isClaimedByCurrentUser {
                        throw ClientError.message(detail: "That invite is no longer available.")
                    }

                    if reservation.isClaimed {
                        guard isClaimedByCurrentUser,
                              User.current()?.status == .active else {
                            throw ClientError.message(detail: "That invite has already been claimed.")
                        }
                        self.invitorId = from
                        self.reservationId = reservationId
                        if let context {
                            await self.applyShareContext(context)
                        }
                        await self.hideLoading()
                        self.delegate.onboardingViewControllerDidResolveActiveInvitation(
                            self,
                            accepted: true
                        )
                        return
                    }

                    guard reservation.status != .declined else {
                        throw ClientError.message(detail: "That invite has been declined.")
                    }

                    if let expiresAt = reservation.expiresAt, expiresAt <= Date() {
                        throw ClientError.message(detail: "That invite has expired.")
                    }

                    self.invitorId = from
                    if let context {
                        await self.applyShareContext(context)
                    } else {
                        try? await self.updateInvitor(userId: from)
                    }
                    self.reservationId = reservationId
                    self.passId = ""
                    self.momentId = ""
                    self.inviteMessage = reservation.inviteMessage ?? self.inviteMessage
                    AnalyticsManager.shared.trackEvent(
                        type: .appClipInvoked,
                        properties: ["kind": "invite"]
                    )
                    AnalyticsManager.shared.trackEvent(
                        type: .appClipPreviewViewed,
                        properties: ["kind": "invite"]
                    )
                    self.welcomeVC.mode = .invitation
                    self.switchTo(.invitation(self.welcomeVC))
                    await self.hideLoading()
                } catch let inviteError as ClientError {
                    await self.hideLoading()
                    let displayError = NSError(
                        domain: "com.jibber.onboarding.invite",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: inviteError.localizedDescription]
                    )
                    await ToastScheduler.shared.schedule(toastType: .error(displayError))
                } catch {
                    await self.hideLoading()
                    let displayError = NSError(
                        domain: "com.jibber.onboarding.invite",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "We couldn't find that invite code. Check the code and make sure it matches this version of Jibber."
                        ]
                    )
                    await ToastScheduler.shared.schedule(toastType: .error(displayError))
                }
            }
        case .pass(passId: let passId):
            self.showLoading()
            Task {
                do {
                    let pass = try await Pass.getObject(with: passId)
                    self.passId = passId
                    guard let userId = pass.owner?.objectId else {
                        throw ClientError.message(detail: "That pass is no longer available.")
                    }
                    try await self.updateInvitor(userId: userId)
                    await self.hideLoading()
                    self.welcomeVC.mode = .pass
                    self.switchTo(.welcome(self.welcomeVC))
                } catch {
                    await self.hideLoading()
                    await ToastScheduler.shared.schedule(toastType: .error(error))
                    return
                }
            }
        case .deepLink(let deepLink):
            if let target = deepLink.deepLinkTarget, target == .moment {
                
            }
        }
    }

    private func respondToInvitation(
        with decision: RespondToReservationInvitation.Decision
    ) {
        guard !self.reservationId.isEmpty else { return }

        self.showLoading()
        Task {
            do {
                _ = try await RespondToReservationInvitation(
                    reservationId: self.reservationId,
                    decision: decision
                ).makeRequest(andUpdate: [], viewsToIgnore: [self.view])
                await self.hideLoading()

                switch decision {
                case .accepted:
                    if User.current()?.status == .active {
                        AnalyticsManager.shared.trackEvent(
                            type: .appClipConnectionCompleted,
                            properties: ["kind": "invite"]
                        )
                        self.delegate.onboardingViewControllerDidResolveActiveInvitation(
                            self,
                            accepted: true
                        )
                    } else {
                        AnalyticsManager.shared.trackEvent(
                            type: .appClipOnboardingStarted,
                            properties: ["kind": "invite"]
                        )
                        self.switchTo(.phone(self.phoneVC))
                    }
                case .declined:
                    if User.current()?.status == .active {
                        self.delegate.onboardingViewControllerDidResolveActiveInvitation(
                            self,
                            accepted: false
                        )
                        return
                    }
                    self.reservationId = ""
                    self.inviteMessage = nil
                    self.welcomeVC.mode = .standard
                    self.switchTo(.welcome(self.welcomeVC))
                    await ToastScheduler.shared.schedule(
                        toastType: .success(.handWave, "Invitation declined")
                    )
                }
            } catch {
                await self.hideLoading()
                await ToastScheduler.shared.schedule(toastType: .error(error))
            }
        }
    }

    @MainActor
    func updateInvitor(userId: String) async throws {
        let user = try await User.getObject(with: userId)
        self.applyInvitor(user, userId: userId)
    }

    @MainActor
    private func applyInvitor(_ user: User, userId: String) {
        self.invitor = user
        self.invitorId = userId
        self.invitorDisplayName = user.givenName
        self.setGuide(
            person: user,
            displayName: user.givenName.capitalized,
            guideUserId: userId
        )
    }

    @MainActor
    func applyShareContext(_ context: [String: Any]) async {
        guard let inviter = context["inviter"] as? [String: Any],
              let firstName = inviter["firstName"] as? String else {
            return
        }

        var image: UIImage?
        if let avatarURL = inviter["avatarURL"] as? String,
           let url = URL(string: avatarURL),
           let (data, _) = try? await URLSession.shared.data(from: url) {
            image = UIImage(data: data)
        }

        self.invitorDisplayName = firstName
        self.inviteMessage = context["inviteMessage"] as? String
        let avatar = SystemAvatar(
            givenName: firstName,
            familyName: "",
            handle: "",
            phoneNumber: nil,
            image: image
        )
        self.setGuide(
            person: avatar,
            displayName: firstName.capitalized,
            guideUserId: self.invitorId
        )
    }

    // MARK: - Loading Animations

    func showLoading() {
        self.loadingBlur.removeFromSuperview()
        self.view.addSubview(self.loadingBlur)
        self.view.layoutNow()
        UIView.animate(withDuration: Theme.animationDurationStandard) {
            self.loadingBlur.showBlur(true)
        } completion: { completed in
            self.loadingAnimationView.play()
        }
    }

    @MainActor
    func hideLoading() async {
        return await withCheckedContinuation { continuation in
            self.loadingAnimationView.stop()
            UIView.animate(withDuration: Theme.animationDurationStandard) {
                self.loadingBlur.effect = nil
            } completion: { completed in
                self.loadingBlur.removeFromSuperview()
                continuation.resume(returning: ())
            }
        }
    }
}
