//
//  TransitionRouter+CrossDissolve.swift
//  Jibber
//
//  Created by Martin Young on 4/25/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import UIKit
import Transitions

extension TransitionRouter {

    /// For presentation, blurs the fromVC then fades in the toVC.
    /// For dismiss, fades out fromVC and unblurs the toVC.
    func blur(transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView

        let isPresenting = self.operation == .push
        if isPresenting {
            // We only need to add the to VC to the container if we're presenting it.
            containerView.addSubview(self.toVC.view)
            self.toVC.navigationController?.navigationBar.alpha = 0
            self.toVC.view.alpha = 0
        }

        let toVCFinalFrame = transitionContext.finalFrame(for: self.toVC)
        if toVCFinalFrame != .zero {
            self.toVC.view.frame = toVCFinalFrame
            self.toVC.view.layoutIfNeeded()
        }

        let blurView = containerView.subviews(type: DarkBlurView.self).first ?? DarkBlurView()
        if isPresenting {
            blurView.showBlur(false)
            containerView.insertSubview(blurView, at: 0)
            blurView.frame = containerView.bounds
        }

        UIView.animateKeyframes(withDuration: self.transitionDuration(using: transitionContext),
                                delay: 0,
                                options: .calculationModeLinear,
                                animations: {

            if isPresenting {
                // Blur out the presenting view.
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                    blurView.showBlur(true)
                }

                // Fade in the presented view.
                UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.7) {
                    self.toVC.view.alpha = 1
                    self.toVC.navigationController?.navigationBar.alpha = 1
                }
            } else {
                // Fade out the presented view.
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                    self.fromVC.view.alpha = 0
                    self.fromVC.navigationController?.navigationBar.alpha = 0
                }

                // Unblur the presenting view.
                UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.7) {
                    blurView.showBlur(false)
                }
            }
        }) { (completed) in
            MainActor.assumeIsolated {
                transitionContext.completeTransition(true)
            }
        }
    }
}
