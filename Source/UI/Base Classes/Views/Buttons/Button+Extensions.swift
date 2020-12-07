//
//  Button+Extensions.swift
//  Benji
//
//  Created by Benji Dodgson on 12/7/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import TMROFutures

extension Button {

    /// Starts a loading animation on the button and hides the text.
    func handleLoadingState() -> Future<Void> {
        let promise = Promise<Void>()

        if !self.alphaOutAnimator.isRunning {
            self.isUserInteractionEnabled = false
            self.isEnabled = false

            self.alphaOutAnimator.stopAnimation(true)

            self.alphaOutAnimator.addAnimations { [unowned self] in
                if let color = self.defaultColor {
                    self.setBackground(color: color.color, forUIControlState: .normal)
                    self.errorLabel.alpha = 0.0
                }
                for view in self.subviews {
                    if let label = view as? UILabel {
                        label.alpha = 0.0
                    }
                }
            }
            self.alphaOutAnimator.startAnimation(afterDelay: 0.1)
            self.alphaOutAnimator.addCompletion { (position) in
                if position == .end {
                    self.animationView.isHidden = false
                    self.animationView.play()
                }
                promise.resolve(with: ())
            }
        }

        return promise
    }

    /// Stops any loading animations and shows the button in its standard color with whatever text is assigned to it.
    func handleNormalState() -> Future<Void> {
        let promise = Promise<Void>()

        if !self.alphaInAnimator.isRunning {
            self.alphaOutAnimator.stopAnimation(true)
            self.alphaInAnimator.stopAnimation(true)
            self.alphaInAnimator.addAnimations { [unowned self] in
                if let color = self.defaultColor{
                    self.setBackground(color: color.color, forUIControlState: .normal)
                }
                for view in self.subviews {
                    if let label = view as? UILabel {
                        // Don't show the error label while we're in the normal button state.
                        label.alpha = label === self.errorLabel ? 0 : 1
                    }
                }
            }
            self.alphaInAnimator.startAnimation()
            self.alphaInAnimator.addCompletion { (position) in
                self.isUserInteractionEnabled = true
                self.isEnabled = true
                promise.resolve(with: ())
            }

            self.animationView.stop()
        }

        return promise
    }

    /// Changes the button to the error color and displays a provided error message on the button.
    func handleError(_ description: String) -> Future<Void> {
        let promise = Promise<Void>()

        // We need to stop this animator in the case that we get an error before the completion is called (which starts the spinner)
        self.alphaOutAnimator.stopAnimation(true)

        // End the loading state
        self.animationView.stop()

        // Update button UI for error state
        //self.errorLabel.setText(description)
        self.isUserInteractionEnabled = true
        self.isEnabled = true

        UIView.animate(withDuration: Theme.animationDuration, animations: {
            for view in self.subviews {
                if let label = view as? UILabel {
                    label.alpha = 0.0
                }
            }
            self.errorLabel.alpha = 1.0
            self.setBackground(color: Color.red.color, forUIControlState: .normal)
        }) { (_) in
            promise.resolve(with: ())
        }

        return promise
    }
}
