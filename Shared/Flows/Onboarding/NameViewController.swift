//
//  LoginNameViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 8/12/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import ParseCore
import Localization

class NameViewController: TextInputViewController<String> {
    
    enum State {
        case noName
        case givenNameValid
        case validFullName
    }
    
    override var analyticsIdentifier: String? {
        return "SCREEN_NAME"
    }
    
    @Published var state: State = .noName

    init() {
        super.init(textField: TextField(), placeholder: LocalizedString(id: "", default: "First Last"))
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        self.textField.autocorrectionType = .yes
        self.textField.textContentType = .name
        self.textField.keyboardType = .namePhonePad
    }

    override func validate(text: String) -> Bool {
        if text.isValidGivenName, !text.isValidFullName {
            self.state = .givenNameValid
        } else if text.isValidFullName {
            self.state = .validFullName
        } else {
            self.state = .noName
        }
        
        return text.isValidFullName
    }

    override func didTapButton() {
        self.updateUserName()
    }

    private func updateUserName() {
        guard let text = self.textField.text, !text.isEmpty else { return }

        guard text.isValidFullName else { return }
        self.complete(with: .success(text))
    }
}
