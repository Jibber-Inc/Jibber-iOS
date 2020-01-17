//
//  SwitchableContentViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 1/14/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ReactiveSwift
import TMROLocalization

class SwitchableContentViewController<ContentType: SwitchableContent>: NavigationBarViewController, KeyboardObservable {

    lazy var currentContent = MutableProperty<ContentType?>(nil)
    private var currentCenterVC: ViewController?

    override func initializeViews() {
        super.initializeViews()

        self.registerKeyboardEvents()

        self.currentContent.producer
            .skipRepeats()
            .on { [unowned self] (contentType) in
                self.switchContent()
        }.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        
    }

    func switchContent() {
        guard let current = self.currentContent.value else { return }

        UIView.animate(withDuration: Theme.animationDuration, animations: {
            self.titleLabel.alpha = 0
            self.titleLabel.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)

            self.descriptionLabel.alpha = 0
            self.descriptionLabel.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)

            self.currentCenterVC?.view.alpha = 0
            self.backButton.alpha = 0

        }) { (completed) in

            self.currentCenterVC?.removeFromParentSuperview()

            self.updateLabels()

            self.currentCenterVC = current.viewController
            let showBackButton = current.shouldShowBackButton

            if let contentVC = self.currentCenterVC {
                self.addChild(viewController: contentVC, toView: self.scrollView)
            }

            self.view.setNeedsLayout()

            UIView.animate(withDuration: Theme.animationDuration) {
                self.titleLabel.alpha = 1
                self.titleLabel.transform = .identity

                self.descriptionLabel.alpha = 1
                self.descriptionLabel.transform = .identity

                self.currentCenterVC?.view.alpha = 1
                self.backButton.alpha = showBackButton ? 1 : 0
            }
        }
    }

    func handleKeyboard(frame: CGRect,
                        with animationDuration: TimeInterval,
                        timingCurve: UIView.AnimationCurve) {

        UIView.animate(withDuration: animationDuration, animations: {
            self.view.layoutNow()
        })
    }

    override func getTitle() -> Localized {
        return self.currentContent.value?.title ?? LocalizedString.empty
    }

    override func getDescription() -> Localized {
        return self.currentContent.value?.description ?? LocalizedString.empty
    }
}
