//
//  File.swift
//  
//
//  Created by Benji Dodgson on 5/30/22.
//

import Foundation
import UIKit

extension TransitionableRouter {

    /// Fades out the fromVC and then fades in the toVC.
    func fadeTransition(transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView

        let isPresenting = self.operation == .push
        if isPresenting {
            // We only need to add the to VC to the container if we're presenting it.
            containerView.addSubview(self.toVC.view)
        }

        self.toVC.navigationController?.navigationBar.alpha = 0
        self.toVC.view.alpha = 0

        let toVCFinalFrame = transitionContext.finalFrame(for: self.toVC)
        if toVCFinalFrame != .zero {
            containerView.addSubview(self.toVC.view)
            self.toVC.view.frame = toVCFinalFrame
            self.toVC.view.layoutIfNeeded()
        }

        UIView.animateKeyframes(withDuration: self.transitionDuration(using: transitionContext),
                                delay: 0,
                                options: .calculationModeLinear,
                                animations: {

                // Fade out the fromVC
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                    self.fromVC.view.alpha = 0
                    self.fromVC.navigationController?.navigationBar.alpha = 0
                }

                // Fade in the toVC
                UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) {
                    self.toVC.view.alpha = 1
                    self.toVC.navigationController?.navigationBar.alpha = 1
                }
        }) { (completed) in
            MainActor.assumeIsolated {
                transitionContext.completeTransition(true)
            }
        }
    }
}
