//
//  newWelcomeViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 12/30/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Coordinator
import Foundation
import ParseCore
import Combine
import Localization
import UIKit

class WelcomeViewController: ViewController, Sizeable, Completable {
    
    typealias ResultType = SelectionType
    
    enum SelectionType {
        case waitlist
        case rsvp
        case acceptInvite
        case declineInvite
        case acceptMomentInvite
        case deferMomentInvite
    }

    enum Mode: Equatable {
        case standard
        case invitation
        case momentInvitation
        case pass
    }

    /// The generic canonical Welcome composer changes in place. Contextual deep
    /// links continue to use ``Mode.invitation``/``Mode.momentInvitation`` and
    /// therefore bypass these generic choices.
    enum CanonicalEntryState: Equatable {
        case choices
        case inviteCode
        case resolvingInvite
    }
    
    var onDidComplete: ((Result<SelectionType, Error>) -> Void)?
    
    let waitlistButton = ThemeButton()
    let rsvpButton = ThemeButton()
    let inviteCodeTextField = TextField()
    private var canonicalAccountChoiceTitle = "Log in or sign up"
    private var canonicalInviteChoiceTitle = "Enter invite code"

    var usesCanonicalEntryChoices = false {
        didSet {
            guard self.isViewLoaded else { return }
            self.updateButtons()
            self.updateEntryStateUI()
        }
    }

    private(set) var canonicalEntryState: CanonicalEntryState = .choices
    /// Once authentication creates an OnboardingSession its guide context is
    /// immutable. Historical Welcome remains visible in the Time Machine, but
    /// generic account/invite controls may no longer mutate that context.
    private(set) var isCanonicalEntryLocked = false
    var onCanonicalEntryStateChanged: ((CanonicalEntryState) -> Void)?
    var onInviteCodeTextChanged: CompletionOptional = nil
    var onResolveInviteCode: ((String) -> Void)?

    var enteredInviteCode: String {
        self.inviteCodeTextField.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var mode: Mode = .standard {
        didSet {
            guard self.isViewLoaded else { return }
            self.updateButtons()
            self.updateEntryStateUI()
        }
    }
        
    override var analyticsIdentifier: String? {
        return "SCREEN_WELCOME"
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.addSubview(self.waitlistButton)
        self.waitlistButton.didSelect { [unowned self] in
            switch self.mode {
            case .standard:
                guard !self.isCanonicalEntryLocked else { return }
                AnalyticsManager.shared.trackEvent(type: .onboardingBeginTapped, properties: nil)
                self.onDidComplete?(.success(.waitlist))
            case .invitation:
                self.onDidComplete?(.success(.acceptInvite))
            case .momentInvitation:
                self.onDidComplete?(.success(.acceptMomentInvite))
            case .pass:
                break
            }
        }
        
        self.view.addSubview(self.rsvpButton)
        self.rsvpButton.didSelect { [unowned self] in
            switch self.mode {
            case .standard:
                guard !self.isCanonicalEntryLocked else { return }
                if self.usesCanonicalEntryChoices {
                    self.showInviteCodeEntry()
                    return
                }
                AnalyticsManager.shared.trackEvent(type: .onboardingRSVPTapped, properties: nil)
                self.onDidComplete?(.success(.rsvp))
            case .invitation:
                self.onDidComplete?(.success(.declineInvite))
            case .momentInvitation:
                self.onDidComplete?(.success(.deferMomentInvite))
            case .pass:
                break
            }
        }

        self.view.addSubview(self.inviteCodeTextField)
        self.inviteCodeTextField.font = FontType.medium.font
        self.inviteCodeTextField.textColor = ThemeColor.white.color
        self.inviteCodeTextField.tintColor = ThemeColor.D6.color
        self.inviteCodeTextField.keyboardAppearance = .dark
        self.inviteCodeTextField.keyboardType = .asciiCapable
        self.inviteCodeTextField.autocorrectionType = .no
        self.inviteCodeTextField.autocapitalizationType = .none
        self.inviteCodeTextField.returnKeyType = .done
        self.inviteCodeTextField.adjustsFontSizeToFitWidth = true
        self.inviteCodeTextField.accessibilityLabel = "Invite code"
        self.inviteCodeTextField.accessibilityIdentifier = "onboarding.inviteCode"
        self.inviteCodeTextField.addTarget(
            self,
            action: #selector(self.inviteCodeDidChange),
            for: .editingChanged
        )
        self.inviteCodeTextField.setPlaceholder(
            attributed: AttributedString(
                LocalizedString(id: "", default: "Enter invite code"),
                fontType: .medium,
                color: .whiteWithAlpha
            )
        )
        self.inviteCodeTextField.setDefaultAttributes(
            style: StringStyle(font: .medium, color: .white),
            alignment: .left
        )

        self.updateButtons()
        self.updateEntryStateUI()
    }

    private func updateButtons() {
        switch self.mode {
        case .standard:
            self.waitlistButton.set(
                style: .custom(
                    color: .D1,
                    textColor: .white,
                    text: self.usesCanonicalEntryChoices
                        ? self.canonicalAccountChoiceTitle
                        : "Join Waitlist / Login"
                )
            )
            self.rsvpButton.set(
                style: .custom(
                    color: .white,
                    textColor: .B0,
                    text: self.usesCanonicalEntryChoices
                        ? self.canonicalInviteChoiceTitle
                        : "Enter Invite Code"
                )
            )
        case .invitation:
            self.waitlistButton.set(
                style: .custom(color: .D1, textColor: .white, text: "Accept Invite")
            )
            self.rsvpButton.set(
                style: .custom(color: .white, textColor: .B0, text: "Decline")
            )
        case .momentInvitation:
            self.waitlistButton.set(
                style: .custom(color: .D1, textColor: .white, text: "Connect & Continue")
            )
            self.rsvpButton.set(
                style: .custom(color: .white, textColor: .B0, text: "Not Now")
            )
        case .pass:
            break
        }
    }

    func setCanonicalChoiceTitles(account: String, invite: String) {
        self.canonicalAccountChoiceTitle = account
        self.canonicalInviteChoiceTitle = invite
        guard self.isViewLoaded else { return }
        self.updateButtons()
    }

    func showChoices(clearInviteCode: Bool = false) {
        guard self.usesCanonicalEntryChoices,
              self.mode == .standard,
              !self.isCanonicalEntryLocked else { return }
        if clearInviteCode {
            self.inviteCodeTextField.text = nil
        }
        self.setCanonicalEntryState(.choices)
    }

    func showInviteCodeEntry() {
        guard self.usesCanonicalEntryChoices,
              self.mode == .standard,
              !self.isCanonicalEntryLocked else { return }
        self.setCanonicalEntryState(.inviteCode)
        self.inviteCodeTextField.becomeFirstResponder()
    }

    func setResolvingInviteCode(_ isResolving: Bool) {
        guard self.usesCanonicalEntryChoices,
              self.mode == .standard,
              !self.isCanonicalEntryLocked else { return }
        self.setCanonicalEntryState(isResolving ? .resolvingInvite : .inviteCode)
        if !isResolving {
            self.inviteCodeTextField.becomeFirstResponder()
        }
    }

    func submitInviteCodeIfPossible() {
        guard !self.isCanonicalEntryLocked,
              self.canonicalEntryState == .inviteCode,
              !self.enteredInviteCode.isEmpty else { return }
        self.onResolveInviteCode?(self.enteredInviteCode)
    }

    @discardableResult
    func returnToChoices() -> Bool {
        guard self.usesCanonicalEntryChoices,
              self.mode == .standard,
              !self.isCanonicalEntryLocked,
              self.canonicalEntryState != .choices else { return false }
        self.inviteCodeTextField.resignFirstResponder()
        self.showChoices()
        return true
    }

    func setCanonicalEntryLocked(_ isLocked: Bool) {
        guard self.isCanonicalEntryLocked != isLocked else { return }
        self.isCanonicalEntryLocked = isLocked
        if isLocked {
            self.inviteCodeTextField.resignFirstResponder()
            self.inviteCodeTextField.text = nil
            self.setCanonicalEntryState(.choices)
        }
        self.updateEntryStateUI()
    }

    private func setCanonicalEntryState(_ state: CanonicalEntryState) {
        guard self.canonicalEntryState != state else { return }
        self.canonicalEntryState = state
        self.updateEntryStateUI()
        self.onCanonicalEntryStateChanged?(state)
    }

    private func updateEntryStateUI() {
        let showsCanonicalField = !self.isCanonicalEntryLocked
            && self.usesCanonicalEntryChoices
            && self.mode == .standard
            && self.canonicalEntryState != .choices
        let hidesChoices = self.isCanonicalEntryLocked
            || showsCanonicalField
            || self.mode == .pass
        self.waitlistButton.isHidden = hidesChoices
        self.rsvpButton.isHidden = hidesChoices
        self.inviteCodeTextField.isHidden = !showsCanonicalField
        self.inviteCodeTextField.isEnabled = self.canonicalEntryState != .resolvingInvite
        self.inviteCodeTextField.isUserInteractionEnabled = self.inviteCodeTextField.isEnabled

        if showsCanonicalField {
            let backAction = UIAccessibilityCustomAction(
                name: "Back to options",
                target: self,
                selector: #selector(self.accessibilityReturnToChoices)
            )
            self.inviteCodeTextField.accessibilityCustomActions = [backAction]
        } else {
            self.inviteCodeTextField.accessibilityCustomActions = nil
        }
        self.view.setNeedsLayout()
    }

    @objc private func inviteCodeDidChange() {
        self.onInviteCodeTextChanged?()
    }

    @objc private func accessibilityReturnToChoices() -> Bool {
        self.returnToChoices()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if self.usesCanonicalEntryChoices,
           self.mode == .standard,
           self.canonicalEntryState != .choices {
            self.inviteCodeTextField.frame = CGRect(
                x: Theme.ContentOffset.standard.value,
                y: 0,
                width: max(
                    0,
                    self.view.width - Theme.ContentOffset.standard.value.doubled
                ),
                height: min(56, self.view.height)
            )
            self.inviteCodeTextField.centerOnY()
            return
        }

        if self.usesCanonicalEntryChoices, self.mode == .standard {
            let gap = Theme.ContentOffset.short.value
            let availableHeight = max(0, self.view.height - gap)
            let buttonHeight = min(Theme.buttonHeight, availableHeight.half)
            self.waitlistButton.frame = CGRect(
                x: 0,
                y: max(0, self.view.halfHeight - buttonHeight - gap.half),
                width: self.view.width,
                height: buttonHeight
            )
            self.rsvpButton.frame = CGRect(
                x: 0,
                y: self.waitlistButton.bottom + gap,
                width: self.view.width,
                height: buttonHeight
            )
            return
        }
        
        self.rsvpButton.setSize(with: self.view.width)
        self.rsvpButton.pinToSafeAreaBottom()
        self.rsvpButton.centerOnX()
        
        self.waitlistButton.setSize(with: self.view.width)
        self.waitlistButton.match(.bottom, to: .top, of: self.rsvpButton, offset: .negative(.standard))
        
        self.waitlistButton.centerOnX()
    }
}
