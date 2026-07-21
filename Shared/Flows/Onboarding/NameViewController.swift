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
    
    enum State: Equatable {
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
        let nextState = self.validationState(for: text)
        if self.state != nextState {
            self.state = nextState
        }

        return nextState == .validFullName
    }

    /// Pure validity used by composer gating. Calling this while laying out the
    /// conversation must not publish a new state and enqueue another UI pass.
    func isSubmissionValid(_ text: String) -> Bool {
        self.validationState(for: text) == .validFullName
    }

    private func validationState(for text: String) -> State {
        if text.isValidGivenName, !text.isValidFullName {
            return .givenNameValid
        }
        if text.isValidFullName {
            return .validFullName
        }
        return .noName
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
