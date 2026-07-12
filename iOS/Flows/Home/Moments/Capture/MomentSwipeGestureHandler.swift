//
//  MomentSwipeGestureHandler.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/23/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

@MainActor
final class MomentSwipeGestureHandler {

    unowned let viewController: MomentCaptureViewController

    var interactionInProgress = false // If we're currently in a create interaction

    let threshold: CGFloat = 10 // Distance, in points, a pan must move vertically before a dismissal
    let distance: CGFloat = 250 // Distance that a pan must move to fully create the moment

    var panStartPoint: CGPoint? // Where the pan gesture began
    
    var animator: UIViewPropertyAnimator?
    
    var didFinish: CompletionOptional = nil

    init(viewController: MomentCaptureViewController) {
        self.viewController = viewController
    }
    
    func handlePan(for view: UIView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handle(pan:)))
        view.addGestureRecognizer(pan)
    }

    @objc func handle(pan: UIPanGestureRecognizer) {
        
        guard self.shouldHandlePan() else { return }

        let currentPoint = pan.location(in: nil)

        switch pan.state {
        case .began:
            self.panStartPoint = currentPoint
        case .changed:

            if self.interactionInProgress {
                let progress = self.progress(currentPoint: currentPoint)
                self.animator?.fractionComplete = progress
            } else if self.panStartPoint.isNil {
                self.panStartPoint = currentPoint
            } else if let startY = self.panStartPoint?.y,
                      currentPoint.y < startY,
                      startY - currentPoint.y > self.threshold {
                
                self.initializeAnimator()
                self.viewController.pausePlayback()
                // Only start interaction if the pan drags far enough
                self.interactionInProgress = true
                self.viewController.state = .uploading
            }

        case .ended, .cancelled, .failed:
            guard let animator = self.animator else { return }
            
            self.viewController.backOffset = nil
            self.interactionInProgress = false
            self.panStartPoint = nil

            if animator.fractionComplete > 0.25 || pan.velocity(in: nil).y > 400  {
                animator.isReversed = false
            } else {
                self.viewController.resumePlayback()
                self.viewController.state = .playback
                animator.isReversed = true
            }
            
            let timing = UISpringTimingParameters(dampingRatio: 0.6)
            let newDuration = UIViewPropertyAnimator(duration: Theme.animationDurationSlow, timingParameters: timing).duration
            let durationFactor = CGFloat(newDuration / animator.duration)
        
            animator.continueAnimation(withTimingParameters: timing, durationFactor: durationFactor)

        case .possible:
            break
        @unknown default:
            break
        }
    }
    
    private func initializeAnimator() {
        
        if let animator = self.animator {
            if animator.state == .stopped {
                animator.finishAnimation(at: .start)
            } else {
                animator.stopAnimation(true)
                animator.finishAnimation(at: .start)
            }
        }
        
        self.viewController.backOffset = nil
                
        self.animator = UIViewPropertyAnimator(duration: 0, curve: .linear, animations: {
            UIView.animateKeyframes(withDuration: 0, delay: 0) {
                
                UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 1.0) {
                    self.viewController.backOffset = 0
                    self.viewController.view.layoutNow()
                }
                
                UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.05) {
                    self.viewController.confirmationLabel.transform = .identity
                    self.viewController.confirmationLabel.alpha = 1
                }
                
                UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.01) {
                    self.viewController.confirmationLabel.alpha = 0 
                    self.viewController.label.alpha = 0 
                    self.viewController.textView.alpha = 0
                    self.viewController.frontCameraView.alpha = 0
                }
            }
        })
        
        self.animator?.addCompletion({ position in
            if position == .end {
                self.didFinish?() 
            }
        })
        
        self.animator?.isUserInteractionEnabled = false
        self.animator?.pausesOnCompletion = false
        self.animator?.pauseAnimation()
    }

    private func progress(currentPoint: CGPoint) -> CGFloat {
        let diff = self.getDistanceOfPan(from: currentPoint)
        let progress = (diff / self.distance)
        return clamp(progress, 0.0, 1.0)
    }
    
    private func getDistanceOfPan(from point: CGPoint) -> CGFloat {
        guard let startY = self.panStartPoint?.y else { return 0.0 }
        return (startY - point.y)
    }
    
    private func shouldHandlePan() -> Bool {
        return self.viewController.state == .uploading || self.viewController.state == .playback
    }
}
