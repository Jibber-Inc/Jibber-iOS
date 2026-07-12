//
//  LoginPhoneViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 8/10/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import PhoneNumberKit
import ParseCore
import Combine
import UIKit

class PhoneViewController: TextInputViewController<PhoneNumber> {
    
    private(set) var isSendingCode: Bool = false
    
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

    override func textFieldDidChange() {
        super.textFieldDidChange()

         if let text = self.textField.text, text.isEmpty {
            self.isSendingCode = false
        }
    }

    override func validate(text: String) -> Bool {
        return self.isPhoneNumberValid()
    }

    override func didTapButton() {
        guard !self.isSendingCode,
              self.isPhoneNumberValid(),
              let phone = self.phoneTextField.text?.parsePhoneNumber(for: self.phoneTextField.currentRegion) else {
                  return
              }

        Task {
            await self.sendCode(to: phone, region: self.phoneTextField.currentRegion)
        }
    }

    private func isPhoneNumberValid() -> Bool {
        guard let phoneString = self.textField.text,
              phoneString.isValidPhoneNumber(for: self.phoneTextField.currentRegion) else {
                  return false
              }

        return true
    }

    private func sendCode(to phone: PhoneNumber, region: String) async {
        await self.button.handleEvent(status: .loading)
        self.isSendingCode = true

        do {
            let installation = try await PFInstallation.getCurrent()

            let _ = try await SendCode(phoneNumber: phone,
                                       region: region,
                                       installationId: installation.installationId)
                .makeRequest()
            await self.button.handleEvent(status: .complete)
            self.complete(with: .success(phone))
        } catch {
            await self.button.handleEvent(status: .error(""))
            self.complete(with: .failure(error))
        }
    }
}
