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
    func onboardingViewControllerDidTakePhoto(_ controller: OnboardingViewController)
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

    var momentId: String = ""
    var inviteMessage: String?

    var invitor: User?
    var invitorId: String?
    var invitorDisplayName: String?

    init(with delegate: OnboardingViewControllerDelegate) {
        self.delegate = delegate
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
            guard let adminId = PFConfig.current().adminUserId else { return }

            do {
                guard self.invitor.isNil,
                      self.reservationId.isEmpty,
                      self.momentId.isEmpty else { return }
                try await self.updateInvitor(userId: adminId)
            } catch {
                return
            }
        }

        self.welcomeVC.onDidComplete = { [unowned self] result in
            switch result {
            case .success(let selection):
                switch selection {
                case .waitlist:
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

        self.phoneVC.onDidComplete = { [unowned self] result in
            switch result {
            case .success(let phone):
                self.delegate.onboardingViewController(self, didEnter: phone)
            case .failure(_):
                break
            }
        }

        self.codeVC.onDidComplete = { [unowned self] result in
            switch result {
            case .success(let conversationId):
                self.delegate.onboardingViewControllerDidVerifyCode(self,
                                                                    andReturnCID: conversationId)
            case .failure(_):
                break
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

        self.photoVC.onDidComplete = { [unowned self] result in
            switch result {
            case .success:
                self.delegate.onboardingViewControllerDidTakePhoto(self)
            case .failure(_):
                break
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.loadingBlur.expandToSuperviewSize()

        self.loadingAnimationView.size = CGSize(width: 18, height: 18)
        self.loadingAnimationView.centerOnXAndY()
    }

    // MARK: - SwitchableContentViewController Overrides

    override func shouldShowLargeAvatar() -> Bool {
        switch self.currentContent {
        case .welcome, .invitation, .momentInvitation, .phone, .code:
            return true
        case .name, .photo, .none:
            return false
        }
    }

    override func willUpdateContent() {
        super.willUpdateContent()
        
        switch self.currentContent {
        case .photo:
            self.nameLabel.isVisible = false 
            self.personView.isVisible = false
            self.messageBubble.isVisible = false
        default:
            self.messageBubble.isVisible = true
            self.personView.isHidden = self.invitor.isNil
            self.nameLabel.isHidden = self.invitor.isNil
        }
    }

    override func didSelectBackButton() {
        super.didSelectBackButton()

        guard let content = self.currentContent else { return }
        switch content {
        case .phone(_):
            if !self.momentId.isEmpty {
                self.welcomeVC.mode = .momentInvitation
                self.switchTo(.momentInvitation(self.welcomeVC))
            } else if self.reservationId.isEmpty {
                self.welcomeVC.mode = .standard
                self.switchTo(.welcome(self.welcomeVC))
            } else {
                self.welcomeVC.mode = .invitation
                self.switchTo(.invitation(self.welcomeVC))
            }
        case .code(_):
            self.switchTo(.phone(self.phoneVC))
        case .photo(_):
            self.switchTo(.name(self.nameVC))
        default:
            break
        }
    }

    override func getMessage() -> Localized? {
        guard let content = self.currentContent else { return nil }
        if case .invitation = content {
            let inviterName = self.invitorDisplayName?.capitalized
                ?? self.invitor?.givenName.capitalized
                ?? "Someone"
            if let inviteMessage = self.inviteMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !inviteMessage.isEmpty {
                return LocalizedString(
                    id: "",
                    arguments: [],
                    default: "\(inviterName) invited you to connect on Jibber.\n\n“\(inviteMessage)”"
                )
            }
            return LocalizedString(
                id: "",
                arguments: [],
                default: "\(inviterName) invited you to connect on Jibber. Accept to verify your number and finish setting up your account."
            )
        }
        if case .momentInvitation = content {
            let inviterName = self.invitorDisplayName?.capitalized
                ?? self.invitor?.givenName.capitalized
                ?? "this person"
            return LocalizedString(
                id: "",
                arguments: [],
                default: "Connect with \(inviterName) to continue. Choose Not Now to return to the Moment without changing anything."
            )
        }
        return content.getDescription(with: self.invitor)
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
            Task {
                do {
                    let pass = try await Pass.getObject(with: passId)
                    self.passId = passId
                    if let userId = pass.owner?.objectId {
                        try await self.updateInvitor(userId: userId)
                        await self.hideLoading()
                        self.switchTo(.phone(self.phoneVC))
                    }
                } catch {
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
        self.invitor = user
        self.invitorId = userId
        self.invitorDisplayName = user.givenName
        self.personView.set(person: user)
        self.nameLabel.setText(user.givenName.capitalized)
        self.personView.isHidden = false
        self.updateUI()
        self.view.layoutNow()
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
        self.personView.set(person: avatar)
        self.nameLabel.setText(firstName.capitalized)
        self.personView.isHidden = false
        self.updateUI()
        self.view.layoutNow()
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
