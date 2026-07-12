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
    
    override var analyticsIdentifier: String? {
        return "SCREEN_CODE"
    }
    
    init() {
        super.init(textField: TextField(), placeholder: LocalizedString(id: "", default: "0000"))
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func validate(text: String) -> Bool {
        return text.extraWhitespaceRemoved().count == 4
    }

    override func didTapButton() {
        guard let code = self.textField.text, code.extraWhitespaceRemoved().count == 4 else { return }

        Task { await self.verify(code: code) }
    }

    // True if we're in the process of verifying the code
    private var verifying: Bool = false
    private func verify(code: String) async {
        guard !self.verifying, let phoneNumber = self.phoneNumber else { return }
        
        self.verifying = true
        await self.button.handleEvent(status: .loading)

        do {
            let installation = try await PFInstallation.getCurrent()
            let dict = try await VerifyCode(code: code,
                                            phoneNumber: phoneNumber,
                                            installationId: installation.installationId)
                .makeRequest()

            self.textField.resignResponder()
            guard let token = dict["sessionToken"] else { return }
            
            try await User.become(withSessionToken: token)
            await self.button.handleEvent(status: .complete)
            self.complete(with: .success((dict["conversationId"])))
        } catch {
            await self.button.handleEvent(status: .error(error.localizedDescription))
            self.complete(with: .failure(ClientError.message(detail: "Verification failed.")))
        }

        self.verifying = false
    }
}
