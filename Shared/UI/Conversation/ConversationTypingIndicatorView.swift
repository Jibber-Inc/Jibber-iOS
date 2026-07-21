//
//  ConversationTypingIndicatorView.swift
//  Jibber
//

import Foundation
import UIKit

/// Presentation-only conversation context text.
///
/// The production conversation typing indicator and onboarding's server-driven
/// input context both use this view. Data-source subscriptions intentionally live
/// outside this type so it remains available to the App Clip.
class ConversationTypingIndicatorView: BaseView {
    private let label = ThemeLabel(font: .small)
    private var presentationGeneration = 0

    private(set) var displayedText: String?

    var hasText: Bool {
        !(self.displayedText?.isEmpty ?? true)
    }

    override func initializeSubviews() {
        super.initializeSubviews()

        self.addSubview(self.label)
        self.label.alpha = 0
        self.label.transform = CGAffineTransform(translationX: -5, y: 0)

        self.label.isAccessibilityElement = false
        self.isAccessibilityElement = false
        self.accessibilityTraits = .staticText
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.label.setSize(withWidth: self.width)
        self.label.pin(.left)
        self.label.pin(.bottom)
    }

    /// Replaces the visible context while preserving the production typing
    /// indicator's existing emphasis treatment.
    func setText(
        _ text: String?,
        highlights: [String] = [],
        animated: Bool = true
    ) {
        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.hideText(animated: animated)
            return
        }

        self.presentationGeneration &+= 1
        self.displayedText = text
        self.label.resetToDefaultAttributes()
        self.label.setText(text)
        highlights.forEach { highlight in
            self.label.add(attributes: [.font: FontType.smallBold.font], to: highlight)
        }

        self.accessibilityLabel = text
        self.isAccessibilityElement = true
        self.layoutNow()

        let changes = {
            self.label.alpha = 1
            self.label.transform = .identity
        }
        if animated {
            UIView.animate(
                withDuration: Theme.animationDurationSlow,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
    }

    /// Compatibility spelling retained for the production typing subscription.
    func animate(text: String, highlights: [String]) {
        self.setText(text, highlights: highlights, animated: true)
    }

    func hideText(animated: Bool = true) {
        self.presentationGeneration &+= 1
        let generation = self.presentationGeneration
        self.displayedText = nil
        self.accessibilityLabel = nil
        self.isAccessibilityElement = false

        let changes = {
            self.label.alpha = 0
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self,
                  self.presentationGeneration == generation else { return }
            // Clear attributed ranges before the next context is presented.
            self.label.setText(nil)
            self.label.resetToDefaultAttributes()
            self.label.transform = CGAffineTransform(translationX: -5, y: 0)
        }

        if animated {
            UIView.animate(
                withDuration: Theme.animationDurationFast,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: changes,
                completion: completion
            )
        } else {
            changes()
            completion(true)
        }
    }
}
