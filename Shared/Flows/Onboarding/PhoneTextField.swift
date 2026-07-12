//
//  PhoneTextField.swift
//  Benji
//
//  Created by Benji Dodgson on 1/18/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import PhoneNumberKitUI
import UIKit

class PhoneTextField: PhoneNumberTextField {
    
    let padding = UIEdgeInsets(top: 0, left: 30 + Theme.ContentOffset.long.value, bottom: 0, right: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Make sure pod is updated to use "" vs " " in shouldChangeCharacter in order to have autocomplete work
        self.withPrefix = false
        self.textContentType = .telephoneNumber
        self.keyboardType = .numbersAndPunctuation
        self.textColor = ThemeColor.white.color
        self.textAlignment = .left
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func textField(_ textField: UITextField,
                            shouldChangeCharactersIn range: NSRange,
                            replacementString string: String) -> Bool {

        // This allows for the case when a user autocompletes a phone number:
        if range == NSRange(location: 0, length: 0), string == "" {
            return true
        } else {
            return super.textField(textField,
                                   shouldChangeCharactersIn: range,
                                   replacementString: string)
        }
    }
    
    override open func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: padding)
    }
    
    override open func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: padding)
    }
    
    override open func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: padding)
    }
}
