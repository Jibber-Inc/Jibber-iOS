//
//  TextField.swift
//  Benji
//
//  Created by Benji Dodgson on 12/31/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie
import Combine
import UIKit

@MainActor
class TextField: UITextField {

    var padding = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

    var onTextChanged: (() -> ())?
    var onEditingEnded: (() -> ())?

    var cancellables = Set<AnyCancellable>()

    init() {
        super.init(frame: .zero)
        self.initialize()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func initialize() {
        self.keyboardAppearance = .dark

        self.publisher(for: \.text)
            .removeDuplicates()
            .mainSink { _ in
                self.onTextChanged?()
            }.store(in: &self.cancellables)

        self.addTarget(self,
                       action: #selector(handleTextChanged),
                       for: UIControl.Event.editingChanged)
        self.addTarget(self,
                       action: #selector(handleEditingEnded),
                       for: [.editingDidEnd, .editingDidEndOnExit])
    }

    @objc private func handleTextChanged() {
        self.onTextChanged?()
    }

    @objc private func handleEditingEnded() {
        self.onEditingEnded?()
    }

    func set(attributed: AttributedString, alignment: NSTextAlignment = .left) {
        self.text = attributed.string.string
        self.setDefaultAttributes(style: attributed.style, alignment: alignment)
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: self.padding)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: self.padding)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: self.padding)
    }
}
