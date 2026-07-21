//
//  LoginPhoneViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 8/10/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import PhoneNumberKit
import PhoneNumberKitUI
import ParseCore
import Combine
import UIKit

class PhoneViewController: TextInputViewController<PhoneNumber> {
    
    private(set) var isSendingCode: Bool = false
    var usesAuthenticatedRestart = false
    var onRequestStateChanged: ((EventStatus) -> Void)?
    
    override var analyticsIdentifier: String? {
        return "SCREEN_PHONE"
    }

    var phoneTextField: PhoneTextField {
        return self.textField as! PhoneTextField
    }

    init() {
        let phoneField = PhoneTextField(frame: .zero)
        phoneField.withFlag = true
        phoneField.withDefaultPickerUI = true
        phoneField.withExamplePlaceholder = true
        phoneField.textColor = ThemeColor.white.color

        super.init(textField: phoneField, placeholder: phoneField.placeholder)

        phoneField.textAlignment = .left
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func shouldBecomeFirstResponder() -> Bool {
        return !self.isPhoneNumberValid()
    }

    override func validate(text: String) -> Bool {
        return self.isPhoneNumberValid()
    }

    override func didTapButton() {
        Task { _ = await self.submitPhoneNumber() }
    }

    /// Performs the full request lifecycle so the shared conversation swipe
    /// driver can retain its single-flight gate until the endpoint settles.
    @discardableResult
    func submitPhoneNumber() async -> Bool {
        guard !self.isSendingCode,
              self.isPhoneNumberValid(),
              let phone = self.phoneTextField.text?.parsePhoneNumber(
                for: self.phoneTextField.currentRegion
              ) else {
            return false
        }

        let region = self.phoneTextField.currentRegion
        self.isSendingCode = true
        defer { self.isSendingCode = false }
        return await self.sendCode(to: phone, region: region)
    }

    private func isPhoneNumberValid() -> Bool {
        guard let phoneString = self.textField.text,
              phoneString.isValidPhoneNumber(for: self.phoneTextField.currentRegion) else {
                  return false
              }

        return true
    }

    private func sendCode(to phone: PhoneNumber, region: String) async -> Bool {
        self.onRequestStateChanged?(.loading)
        await self.button.handleEvent(status: .loading)

        do {
            if self.usesAuthenticatedRestart {
                let response = try await RestartOnboardingVerificationV1(
                    phoneNumber: phone
                ).makeRequest()
                guard response.sent else {
                    throw ClientError.message(detail: "A verification code could not be sent.")
                }
            } else {
                let installation = try await PFInstallation.getCurrent()
                _ = try await SendCode(
                    phoneNumber: phone,
                    region: region,
                    installationId: installation.installationId
                ).makeRequest()
            }
            await self.button.handleEvent(status: .complete)
            self.onRequestStateChanged?(.complete)
            self.complete(with: .success(phone))
            return true
        } catch {
            await self.button.handleEvent(status: .error(""))
            self.onRequestStateChanged?(.error(error.localizedDescription))
            self.complete(with: .failure(error))
            return false
        }
    }
}
