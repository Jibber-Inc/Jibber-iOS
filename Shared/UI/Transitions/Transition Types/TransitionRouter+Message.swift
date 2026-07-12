//
//  TransitionRouter+Message.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/18/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Transitions
import UIKit 

protocol MessageInteractableController where Self: DismissInteractableController {
    var blurView: DarkBlurView { get set }
    var messageContent: MessageContentView? { get }
    func handleDismissal()
    func handleInitialDismissal()
    func handleCompletedDismissal()
    func prepareForPresentation()
    func handleFinalPresentation()
    func handlePresentationCompleted()
}

extension MessageInteractableController {
    func prepareForPresentation() {}
    func handleCompletedDismissal() {}
}

extension TransitionRouter {

    func messageTranstion(fromView: MessageContentView,
                          toView: MessageContentView,
                          transitionContext: UIViewControllerContextTransitioning) {

        if self.toVC is MessageInteractableController {
            self.presentInteractableMessageVC(fromView: fromView, toView: toView, transitionContext: transitionContext)
        }
    }

    private func presentInteractableMessageVC(fromView: MessageContentView,
                                              toView: MessageContentView,
                                              transitionContext: UIViewControllerContextTransitioning) {

        guard let interactableVC = self.toVC as? MessageInteractableController,
                let message = fromView.message else { return }

        // Make sure we have all the components we need to complete this transition
        let snapshot = MessageContentView()

        snapshot.configure(with: message)
        snapshot.bubbleView.setBubbleColor(fromView.bubbleView.bubbleColor, animated: false)
        snapshot.bubbleView.tailLength = 0
        snapshot.bubbleView.orientation = fromView.bubbleView.orientation
        snapshot.size = fromView.bubbleView.bubbleFrame.size

        toView.configure(with: message)
        toView.bubbleView.setBubbleColor(ThemeColor.B6.color, animated: false)
        toView.textView.setTextColor(.white)
        toView.bubbleView.tailLength = 0
        toView.bubbleView.orientation = fromView.bubbleView.orientation
        toView.size = fromView.bubbleView.bubbleFrame.size
        toView.layoutNow()

        snapshot.frame = fromView.frame

        let containerView = transitionContext.containerView
        containerView.set(backgroundColor: .clear)
        fromView.isHidden = true

        let toVCFinalFrame = transitionContext.finalFrame(for: self.toVC)
        self.toVC.view.frame = toVCFinalFrame

        containerView.addSubview(self.toVC.view)
        self.toVC.view.layoutIfNeeded()

        containerView.addSubview(snapshot)
        let finalFrame = toView.convert(toView.bounds, to: containerView)

        self.toVC.view.alpha = 0
        interactableVC.blurView.showBlur(false)

        // Put snapshot in the exact same spot as the original so that the transition looks seamless
        snapshot.frame = fromView.convert(fromView.bounds, to: containerView)

        toView.alpha = 0

        interactableVC.prepareForPresentation()
        Task {
            async let first: () = UIView.awaitSpringAnimation(with: .slow, animations: {
                snapshot.frame = finalFrame
                interactableVC.blurView.showBlur(true)
                self.toVC.view.alpha = 1
            })

            async let second: () = UIView.awaitAnimation(with: .fast, delay: 0.25, animations: {
                toView.alpha = 1
                interactableVC.handleFinalPresentation()
            })

            let _: [()] = await [first, second]

            interactableVC.handlePresentationCompleted()
            
            snapshot.removeFromSuperview()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }.add(to: self.taskPool)
    }
}
