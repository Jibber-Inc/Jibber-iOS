//
//  SwipeInputHintAnimator.swift
//  Jibber
//
//  Created by Martin Young on 2/23/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

/// Manages hint animations on behalf of a SwipeableInputAccessoryView.
@MainActor
final class SwipeInputHintAnimator {

    private weak var view: SwipeableInputAccessoryView?

    init(swipeInputView: SwipeableInputAccessoryView) {
        self.view = swipeInputView
    }

    private var swipeHintTask: Task<Void, Never>?

    /// Cancels any existing animation sequences. If shouldPlay is true, a new animation sequence will start after a delay.
    func updateSwipeHint(shouldPlay: Bool) {
        // Cancel any currently running swipe hint tasks so we don't trigger the animation multiple times.
        self.swipeHintTask?.cancel()

        self.view?.inputContainerView.transform = .identity
        self.view?.addView.alpha = 1.0

        guard shouldPlay, UserDefaultsManager.getInt(for: .numberOfSwipeHints) < 3 else { return }
            
        self.swipeHintTask = Task { [weak self] in
            guard let self else { return }
            guard let swipeView = self.view else { return }
            
            // Wait a bit before playing the hint
            await Task.snooze(seconds: 3)

            guard !Task.isCancelled else { return }
            
            swipeView.typingIndicatorView.animate(text: "Swipe up to send", highlights: ["Swipe"])
            
            await Task.snooze(seconds: 1.5)
            
            guard !Task.isCancelled else { return }
            
            swipeView.typingIndicatorView.hideText()

            await UIView.awaitSpringAnimation(with: .slow,
                                              damping: 0.2,
                                              options: [.curveEaseInOut, .allowUserInteraction]) {
                swipeView.inputContainerView.transform = CGAffineTransform(translationX: 0.0, y: -4.0)
            }

            guard !Task.isCancelled else { return }

            await UIView.awaitSpringAnimation(with: .slow, options: [.curveEaseInOut, .allowUserInteraction]) {
                swipeView.inputContainerView.transform = .identity
            }

            guard !Task.isCancelled else { return }

            await UIView.awaitSpringAnimation(with: .slow,
                                              damping: 0.2,
                                              options: [.curveEaseInOut, .allowUserInteraction]) {
                swipeView.inputContainerView.transform = CGAffineTransform(translationX: 0.0, y: -4.0)
            }

            guard !Task.isCancelled else { return }

            await UIView.awaitSpringAnimation(with: .slow, options: [.curveEaseInOut, .allowUserInteraction]) {
                swipeView.inputContainerView.transform = .identity
            }
        }
    }
}
