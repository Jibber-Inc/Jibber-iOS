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
                self.messageBubble.alpha = 0
                self.textView.alpha = 0
                self.currentCenterVC?.view.alpha = 0
            })
            
            guard !Task.isCancelled else { return }
            
            self.currentCenterVC?.removeFromParentAndSuperviewIfNeeded()
            self.updateUI()
            self.currentCenterVC = content.viewController

            if let contentVC = self.currentCenterVC {
                self.addChild(contentVC)
                self.view.insertSubview(contentVC.view, belowSubview: self.nameLabel)
            }

            self.willUpdateContent()
            self.view.layoutNow()
            
            await UIView.awaitAnimation(with: .standard, animations: {
                if self.textView.text.exists {
                    self.messageBubble.alpha = 1
                    self.textView.alpha = 1
                }
                
                self.currentCenterVC?.view.alpha = 1
            })
        }
    }

    /// Called whenever a new content vc is about to be presented.
    func willUpdateContent() {}
}
