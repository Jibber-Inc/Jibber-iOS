//
//  LoginCodeViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 8/10/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import KeyboardManager
import PhoneNumberKit
import ParseCore
import Combine
import Localization

@MainActor
class CodeViewController: TextInputViewController<String?> {

    var phoneNumber: PhoneNumber?
    var reservationId: String?
    var passId: String?
    var momentId: String?
    var usesCanonicalConversation = false
    var contextProvider: (() -> OnboardingEntryContext)?
    var localeProvider: (() -> String?)?
    var onRequestStateChanged: ((EventStatus) -> Void)?
    private(set) var canonicalVerificationResponse: OnboardingVerificationResponse?
    private var isReviewingCompletedStep = false
    
    override var analyticsIdentifier: String? {
        return "SCREEN_CODE"
    }
    
    init() {
        super.init(textField: TextField(), placeholder: LocalizedString(id: "", default: "0000"))
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        self.textField.keyboardType = .numberPad
        self.textField.textContentType = .oneTimeCode
        self.textField.autocorrectionType = .no
        self.textField.autocapitalizationType = .none
    }

    override func validate(text: String) -> Bool {
        self.normalizedCode(from: text) != nil
    }

    override func didTapButton() {
        Task { _ = await self.submitCode() }
    }

    /// Performs verification through completion so the shared swipe driver
    /// cannot start a duplicate request while authentication is still active.
    @discardableResult
    func submitCode() async -> Bool {
        guard let text = self.textField.text,
              let code = self.normalizedCode(from: text) else { return false }
        return await self.verify(code: code)
    }

    private func normalizedCode(from text: String) -> String? {
        let code = text.filter { !$0.isWhitespace }
        guard code.count == 4,
              code.allSatisfy(\.isNumber) else { return nil }
        return code
    }

    override func shouldBecomeFirstResponder() -> Bool {
        !self.isReviewingCompletedStep
    }

    /// Verification codes are credentials, not onboarding drafts. Once the
    /// server accepts an attempt they are immediately removed and are never
    /// reconstructed when a completed step is reviewed.
    func clearSensitiveCode() {
        self.textField.text = nil
        self.textField.sendActions(for: .editingChanged)
        self.textField.resignFirstResponder()
    }

    func prepareForReview() {
        self.isReviewingCompletedStep = true
        self.setEmbeddedComposerReviewing(true)
        self.clearSensitiveCode()
    }

    func prepareForEditing() {
        self.isReviewingCompletedStep = false
        self.setEmbeddedComposerReviewing(false)
        self.clearSensitiveCode()
    }

    // True if we're in the process of verifying the code
    private var verifying: Bool = false
    private func verify(code: String) async -> Bool {
        guard !self.verifying, let phoneNumber = self.phoneNumber else { return false }

        self.verifying = true
        defer { self.verifying = false }
        self.canonicalVerificationResponse = nil
        self.onRequestStateChanged?(.loading)
        await self.button.handleEvent(status: .loading)

        do {
            if self.usesCanonicalConversation {
                let response = try await ValidateCodeV2(
                    code: code,
                    phoneNumber: phoneNumber,
                    context: self.contextProvider?() ?? OnboardingEntryContext(
                        reservationId: self.reservationId,
                        passId: self.passId,
                        momentId: self.momentId
                    ),
                    locale: self.localeProvider?()
                ).makeRequest()
                self.clearSensitiveCode()
                try await User.become(withSessionToken: response.sessionToken)
#if !APPCLIP && !NOTIFICATION
                if let user = User.current() {
                    do {
                        try await ParseMessagingManager.shared.initialize(for: user)
                    } catch {
                        // Verification is authoritative. The Parse timeline
                        // provider retries initialization before synchronizing,
                        // so a transient messaging bootstrap failure must not
                        // turn a successful OTP into a failed login.
                        logError(error)
                    }
                }
#endif
                self.canonicalVerificationResponse = response
                await self.button.handleEvent(status: .complete)
                self.onRequestStateChanged?(.complete)
                self.complete(with: .success(response.session.conversationId))
                return true
            } else {
                let installation = try await PFInstallation.getCurrent()
                let dict = try await VerifyCode(
                    code: code,
                    phoneNumber: phoneNumber,
                    installationId: installation.installationId
                ).makeRequest()

                self.clearSensitiveCode()
                guard let token = dict["sessionToken"], !token.isEmpty else {
                    throw ClientError.apiError(detail: "Verification did not return a session.")
                }

                try await User.become(withSessionToken: token)
                await self.button.handleEvent(status: .complete)
                self.onRequestStateChanged?(.complete)
                self.complete(with: .success(dict["conversationId"]))
                return true
            }
        } catch {
            await self.button.handleEvent(status: .error(error.localizedDescription))
            self.onRequestStateChanged?(.error(error.localizedDescription))
            self.complete(with: .failure(ClientError.message(detail: "Verification failed.")))
            return false
        }
    }
}
