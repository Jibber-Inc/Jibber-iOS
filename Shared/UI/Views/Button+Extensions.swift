//
//  Button+Extensions.swift
//  Benji
//
//  Created by Benji Dodgson on 12/7/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie
import UIKit

extension ThemeButton {

    @MainActor
    /// Starts a loading animation on the button and hides the text.
    func handleLoadingState() async {
        return await withCheckedContinuation { continuation in
            if !self.alphaOutAnimator.isRunning {
                self.isUserInteractionEnabled = false

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

                self.alphaOutAnimator.addCompletion { (position) in
                    continuation.resume(returning: ())
                }

                self.animationView.isHidden = false
                self.animationView.play()

                self.alphaOutAnimator.startAnimation()
            }
        }
    }

    @MainActor
    /// Stops any loading animations and shows the button in its standard color with whatever text is assigned to it.
    func handleNormalState() async {
        return await withCheckedContinuation { continuation in
            if !self.alphaInAnimator.isRunning {
                self.alphaOutAnimator.stopAnimation(true)
                self.alphaInAnimator.stopAnimation(true)
                self.alphaInAnimator.addAnimations { [unowned self] in
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
                    continuation.resume(returning: ())
                }

                self.animationView.stop()
            }
        }
    }

    @MainActor
    /// Changes the button to the error color and displays a provided error message on the button.
    func handleError(_ description: String) async {
        return await withCheckedContinuation { continuation in
            // We need to stop this animator in the case that we get an error before the completion is called (which starts the spinner)
            self.alphaOutAnimator.stopAnimation(true)

            // End the loading state
            self.animationView.stop()

            // Update button UI for error state
            //self.errorLabel.setText(description)
            self.isUserInteractionEnabled = true
            self.isEnabled = true

            UIView.animate(withDuration: Theme.animationDurationStandard, animations: {
                for view in self.subviews {
                    if let label = view as? UILabel {
                        label.alpha = 0.0
                    }
                }
                self.errorLabel.alpha = 1.0
            }) { (_) in
                continuation.resume(returning: ())
            }
        }
    }
}
