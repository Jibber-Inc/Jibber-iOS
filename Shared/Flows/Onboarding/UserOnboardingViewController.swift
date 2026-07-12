//
//  UserOnboardingViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/22/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Coordinator
import Foundation
import Lottie
import Localization
import UIKit

class OnboardingPersonView: BorderedPersonView {
    
    override func set(expression: Expression? = nil, person: PersonType?) {
        super.set(expression: expression, person: person)
        self.pulseLayer.borderColor = ThemeColor.D6.color.cgColor
        self.shadowLayer.shadowColor = ThemeColor.D6.color.cgColor
    }
}

class UserOnboardingViewController: ViewController {

    private(set) var personView = OnboardingPersonView()

    private(set) var nameLabel = ThemeLabel(font: .regularBold)
    private(set) var messageBubble = SpeechBubbleView(orientation: .up, bubbleColor: .D1)
    private(set) var textView = OnboardingMessageTextView()

    override func initializeViews() {
        super.initializeViews()
        
        self.personView.isHidden = true 

        self.view.addSubview(self.nameLabel)
        self.view.addSubview(self.personView)
        self.personView.didSelect { [unowned self] in
            self.didSelectBackButton()
        }
        
        self.view.addSubview(self.messageBubble)
        self.messageBubble.addSubview(self.textView)
        self.textView.setTextColor(.white)

        self.updateUI()
    }

    func updateUI(animateTyping: Bool = true) {
        if let text = self.getMessage() {
            self.textView.isHidden = false
            self.messageBubble.isHidden = false
            self.textView.setText(text)
            self.view.layoutNow()
        } else {
            self.textView.isHidden = false
            self.messageBubble.isHidden = false
        }
    }

    func shouldShowLargeAvatar() -> Bool {
        return false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.nameLabel.setSize(withWidth: self.view.width)
        self.nameLabel.centerOnX()
        self.nameLabel.pinToSafeArea(.top, offset: .noOffset)

        let height: CGFloat = self.shouldShowLargeAvatar() ? self.view.width * 0.35 : 60
        self.personView.setSize(forHeight: height)
        self.personView.centerOnX()
        self.personView.match(.top, to: .bottom, of: self.nameLabel, offset: .standard)

        let maxWidth = self.view.width - Theme.ContentOffset.screenPadding.value.doubled
        self.textView.setSize(withMaxWidth: maxWidth)
        
        self.messageBubble.size = self.textView.size
        self.messageBubble.size.width += Theme.ContentOffset.long.value.doubled
        self.messageBubble.size.height += Theme.ContentOffset.long.value.doubled
        
        self.messageBubble.match(.top, to: .bottom, of: self.personView, offset: .standard)
        self.messageBubble.centerOnX()
        
        self.textView.centerOnX()
        self.textView.pin(.bottom, offset: .custom(6))
    }

    // MARK: PUBLIC

    func getMessage() -> Localized? {
        return nil
    }

    func didSelectBackButton() { }
}

class OnboardingMessageTextView: TextView {
    
    init() {
        super.init(frame: .zero,
                   font: .small,
                   textColor: .white,
                   alignment: .center,
                   textContainer: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()

        self.isEditable = false
        self.isScrollEnabled = false
        self.isSelectable = false
        self.textAlignment = .center
        self.textContainer.lineBreakMode = .byWordWrapping
        self.isEditable = false
        self.lineSpacing = 2
    }
}
