//
//  SwitchableContentViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 1/14/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import UIKit

class SwitchableContentViewController<ContentType: Switchable>: UserOnboardingViewController {

    private(set) var currentContent: ContentType?
    private var currentCenterVC: (UIViewController & Sizeable)?

    private var prepareAnimator: UIViewPropertyAnimator?
    private var presentAnimator: UIViewPropertyAnimator?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.currentCenterVC?.view.expandToSuperviewSize()
    }
    
    /// The currently running switch task that is presenting the content.
    private var switchTask: Task<Void, Never>?

    func switchTo(_ content: ContentType) {
        self.switchTask?.cancel()
        self.currentContent = content

        self.switchTask = Task { [weak self] in
            guard let self else { return }

            await UIView.awaitAnimation(with: .standard, animations: {
                self.currentCenterVC?.view.alpha = 0
            })

            guard !Task.isCancelled else { return }

            self.currentCenterVC?.removeFromParentAndSuperviewIfNeeded()
            self.currentCenterVC = content.viewController

            if let contentVC = self.currentCenterVC {
                contentVC.view.alpha = 0
                self.addChild(contentVC)
                self.hostOnboardingContentView(contentVC.view)
                contentVC.didMove(toParent: self)
            } else {
                self.hostOnboardingContentView(nil)
            }

            self.willUpdateContent()
            self.updateUI()
            self.view.layoutNow()

            await UIView.awaitAnimation(with: .standard, animations: {
                self.currentCenterVC?.view.alpha = 1
            })
        }
    }

    /// Called whenever a new content vc is about to be presented.
    func willUpdateContent() {}
}
