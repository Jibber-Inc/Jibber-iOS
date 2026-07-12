//
//  DisclosureModalViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 10/27/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Coordinator
import Foundation
import Localization
import UIKit
 
struct HightlightedPhrase {
    var text: Localized
    var highlightedWords: [Localized]
}

class DisclosureModalViewController: ViewController {

    let titleLabel = ThemeLabel(font: .mediumBold)
    let descriptionLabel = ThemeLabel(font: .regular)
    let contentView = BaseView()

    override func initializeViews() {
        super.initializeViews()

        self.view.set(backgroundColor: .B0)
        self.view.addSubview(self.titleLabel)
        self.titleLabel.textAlignment = .center
        self.view.addSubview(self.descriptionLabel)
        self.descriptionLabel.textAlignment = .center
        
        self.view.addSubview(self.contentView)

        self.modalPresentationStyle = .popover
        if let pop = self.popoverPresentationController {
            let sheet = pop.adaptiveSheetPresentationController
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let maxWidth = Theme.getPaddedWidth(with: self.view.width)

        self.titleLabel.setSize(withWidth: maxWidth)
        self.titleLabel.centerOnX()
        self.titleLabel.pinToSafeArea(.top, offset: .custom(30))

        self.descriptionLabel.setSize(withWidth: maxWidth)
        self.descriptionLabel.centerOnX()
        self.descriptionLabel.match(.top, to: .bottom, of: self.titleLabel, offset: .custom(20))

        let contentHeight = self.view.height - (self.descriptionLabel.bottom + Theme.ContentOffset.long.value) - self.view.safeAreaInsets.bottom
        self.contentView.size = CGSize(width: maxWidth, height: contentHeight)
        self.contentView.match(.top, to: .bottom, of: self.descriptionLabel, offset: .standard)
        self.contentView.centerOnX()
    }

    func updateDescription(with phrase: HightlightedPhrase) {
        self.descriptionLabel.setText(phrase.text)
        phrase.highlightedWords.forEach { highlight in
            self.descriptionLabel.add(attributes: [.font: FontType.regularBold.font], to: localized(highlight))
        }
        self.view.layoutNow()
    }
}
