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
        self.isUserInteractionEnabled = false
        self.alphaInAnimator.stopAnimation(true)
        self.alphaOutAnimator.stopAnimation(true)

        if let color = self.defaultColor {
            self.setBackground(color: color.color, forUIControlState: .normal)
        }
        self.errorLabel.alpha = 0.0
        for view in self.subviews {
            if let label = view as? UILabel {
                label.alpha = 0.0
            }
        }

        self.animationView.isHidden = false
        self.animationView.play()
    }

    @MainActor
    /// Stops any loading animations and shows the button in its standard color with whatever text is assigned to it.
    func handleNormalState() async {
        self.alphaOutAnimator.stopAnimation(true)
        self.alphaInAnimator.stopAnimation(true)
        for view in self.subviews {
            if let label = view as? UILabel {
                // Don't show the error label while we're in the normal button state.
                label.alpha = label === self.errorLabel ? 0 : 1
            }
        }
        self.animationView.stop()
        self.isUserInteractionEnabled = true
        self.isEnabled = true
    }

    @MainActor
    /// Changes the button to the error color and displays a provided error message on the button.
    func handleError(_ description: String) async {
        self.alphaOutAnimator.stopAnimation(true)
        self.alphaInAnimator.stopAnimation(true)
        self.animationView.stop()

        self.errorLabel.setText(description)
        for view in self.subviews {
            if let label = view as? UILabel {
                label.alpha = 0.0
            }
        }
        self.errorLabel.alpha = 1.0
        self.isUserInteractionEnabled = true
        self.isEnabled = true
    }
}
