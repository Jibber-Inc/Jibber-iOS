//
//  File.swift
//  
//
//  Created by Benji Dodgson on 5/30/22.
//

import Foundation
import UIKit

extension TransitionableRouter {

    func moveTranstion(fromView: UIView,
                       toView: UIView,
                       transitionContext: UIViewControllerContextTransitioning) {

        // Make sure we have all the components we need to complete this transition
        guard let snapshot = fromView.snapshotView(afterScreenUpdates: false) else {
            return
        }

        let containerView = transitionContext.containerView
        containerView.backgroundColor = .clear 
        fromView.isHidden = true

        // Clear the background color of the toVC so that it doesn't have a visible seam
        // at the top as it slides up

        let toVCFinalFrame = transitionContext.finalFrame(for: self.toVC)
        self.toVC.view.frame = toVCFinalFrame

        containerView.addSubview(self.toVC.view)
        self.toVC.view.layoutIfNeeded()

        containerView.addSubview(snapshot)
        let finalFrame = toView.convert(toView.bounds, to: containerView)

        self.toVC.view.frame = toVCFinalFrame
        self.toVC.view.alpha = 0

        // Put snapshot in the exact same spot as the original so that the transition looks seamless
        snapshot.frame = fromView.convert(fromView.bounds, to: containerView)

        toView.alpha = 0
        fromView.alpha = 0
        self.toVC.navigationController?.navigationBar.alpha = 0

        let moveDuration = self.transitionDuration(using: transitionContext) * 0.65

        // Broke this out to get the timing curve to work.
        UIView.animate(withDuration: moveDuration,
                       delay: 0.0,
                       options: .curveEaseInOut,
                       animations: {
                        snapshot.frame = finalFrame
        }) { (_) in}

        UIView.animateKeyframes(withDuration: self.transitionDuration(using: transitionContext),
                                delay: 0,
                                options: .calculationModeLinear,
                                animations: {

                                    // Fade out the fromVC
                                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25) {
                                        self.fromVC.view.alpha = 0
                                    }

                                    // Slide toVC into place and fade in tab container, have center content
                                    // and nav bar hidden
                                    UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.2) {
                                        self.toVC.navigationController?.navigationBar.alpha = 0
                                    }

                                    // Fade in view of toVC
                                    UIView.addKeyframe(withRelativeStartTime: 0.65, relativeDuration: 0.35) {
                                        toView.alpha = 1
                                        self.toVC.view.alpha = 1
                                        self.toVC.navigationController?.navigationBar.alpha = 1
                                    }
        }) { (completed) in
            MainActor.assumeIsolated {
                snapshot.removeFromSuperview()
                // UIKit executes animation completions on the main thread.
                self.fromVC.view.alpha = 1
                fromView.isHidden = false
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
        }
    }
}
