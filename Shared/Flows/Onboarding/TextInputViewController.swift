//
//  LoginTextInputViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 8/10/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Coordinator
import Localization
import UIKit
import KeyboardManager
 
class TextFieldToolBar: UIToolbar {

    init(button: UIBarButtonItem) {
        super.init(frame: .init(origin: .zero,
                                size: CGSize(width: 0,
                                             height: Theme.buttonHeight + Theme.ContentOffset.standard.value.doubled)))
        self.autoresizingMask = [.flexibleWidth]
        self.setItems([button], animated: false)
        self.isTranslucent = true
        self.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        self.set(backgroundColor: .clear)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TextInputViewController<ResultType>: ViewController, Sizeable, Completable, UITextFieldDelegate {

    var onDidComplete: ((Result<ResultType, Error>) -> Void)?

    /// Canonical onboarding owns its Back and primary controls in the shared
    /// conversation composer. The legacy keyboard toolbar remains available to
    /// released clients that still use the original presentation.
    var usesEmbeddedComposer = false {
        didSet {
            self.textEntry.set(
                style: self.usesEmbeddedComposer
                    ? .conversationComposer
                    : .standard
            )
        }
    }
    private(set) var isReviewingEmbeddedComposer = false

    func setEmbeddedComposerReviewing(_ isReviewing: Bool) {
        self.isReviewingEmbeddedComposer = isReviewing
        self.textField.isEnabled = !isReviewing
        self.textField.isUserInteractionEnabled = !isReviewing
        if isReviewing {
            self.textField.resignFirstResponder()
            self.textField.inputAccessoryView = nil
            self.textField.reloadInputViews()
        } else {
            self.textField.sendActions(for: .editingChanged)
        }
    }

    var textField: UITextField {
        return self.textEntry.textField
    }

    private(set) var textEntry: TextEntryField

    lazy var button: ThemeButton = {
        let button = ThemeButton()
        button.set(style: .custom(color: .white, textColor: .B0, text: "Next"))
        button.height = Theme.buttonHeight
        button.didSelect { [unowned self] in
            self.didTapButton()
        }
        return button
    }()

    lazy var barButton: UIBarButtonItem = {
        let barButton = UIBarButtonItem.init(customView: self.button)
        // iOS 26+ gives toolbar items a shared glass background by default.
        // This button already supplies its own background and loading state;
        // letting the toolbar add glass causes repeated glass updates while the
        // loading animation starts and can leave the input accessory frozen.
        barButton.hidesSharedBackground = true
        return barButton
    }()

    lazy var toolbar = TextFieldToolBar(button: self.barButton)

    init(textField: UITextField, placeholder: Localized?) {
        self.textEntry = TextEntryField(with: textField, placeholder: placeholder)
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        self.view.addSubview(self.textEntry)

        self.textEntry.textField.addTarget(self,
                                           action: #selector(textFieldDidChange),
                                           for: UIControl.Event.editingChanged)
        self.textEntry.textField.delegate = self

        KeyboardManager.shared.$cachedKeyboardEndFrame.mainSink { [weak self] _ in
            guard let self else { return }
            UIView.animate(withDuration: 0.01) {
                self.view.setNeedsLayout()
            }
        }.store(in: &self.cancellables)
    }

    func didTapButton() {}

    func setActionTitle(_ title: Localized) {
        self.button.set(style: .custom(color: .white, textColor: .B0, text: title))
    }

    @objc func textFieldDidChange() {
        guard let text = self.textField.text else {
            self.textField.inputAccessoryView = nil
            self.textField.autocorrectionType = .default
            self.textField.reloadInputViews()
            return
        }

        let isValid = self.validate(text: text)

        self.textField.inputAccessoryView = isValid && !self.usesEmbeddedComposer
            ? self.toolbar
            : nil
        self.textField.autocorrectionType = isValid ? .no : .default
        self.textField.reloadInputViews()
    }

    func validate(text: String) -> Bool {
        return false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = self.view.width - Theme.ContentOffset.long.value.doubled
        let height = self.textEntry.getHeight(for: width)
        self.textEntry.size = CGSize(width: width, height: height)
        self.textEntry.centerOnX()

        // The onboarding controls now live inside the focused Time Machine card rather than a
        // full-screen child. Convert the global keyboard frame into this local coordinate space
        // so the input stays centered in the visible portion of either presentation.
        let keyboardFrame = KeyboardManager.shared.cachedKeyboardEndFrame
        let localKeyboardTop = self.view.convert(keyboardFrame, from: nil).minY
        let keyboardIsVisible = keyboardFrame.height > 0 && localKeyboardTop < self.view.height
        let visibleBottom = keyboardIsVisible ? localKeyboardTop : self.view.height
        let minimumCenter = height.half + Theme.ContentOffset.long.value
        let maximumCenter = max(minimumCenter,
                                visibleBottom - height.half - Theme.ContentOffset.long.value)
        self.textEntry.centerY = clamp(self.view.height * 0.52,
                                       minimumCenter,
                                       maximumCenter)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.becomeFirstResponder()

        if !self.isReviewingEmbeddedComposer,
           self.shouldBecomeFirstResponder() {
            self.textEntry.textField.becomeFirstResponder()
        }
    }

    func shouldBecomeFirstResponder() -> Bool {
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {}
}
