//
//  InputTextView.swift
//  Benji
//
//  Created by Benji Dodgson on 8/30/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

enum InputType {
    case keyboard
}

class InputTextView: ExpandingTextView {

    private(set) var currentInputType: InputType?
    @Published var inputText: String = ""

    func updateInputView(type: InputType, becomeFirstResponder: Bool = true) {
        defer {
            if becomeFirstResponder, !self.isFirstResponder {
                self.becomeFirstResponder()
            }
        }
        
        guard self.currentInputType != type else { return }

        switch type {
        case .keyboard:
            self.inputView = nil
        }

        self.currentInputType = type
        self.reloadInputViews()
    }

    override func textDidChange() {
        super.textDidChange()
        
        self.inputText = self.text
    }
}
