//
//  MessageTextView.swift
//  Jibber
//

import Foundation
import Localization
import UIKit

/// Provider-neutral message text presentation shared by the full app and App Clip.
class MessageTextView: TextView {

    override func initializeViews() {
        super.initializeViews()

        self.isEditable = false
        self.isScrollEnabled = false
        self.isSelectable = true
        self.textContainerInset = .zero
    }

    func setText(with message: Messageable) {
        self.animationTask?.cancel()
        self.setText(message.kind.text)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        var location = point
        location.x -= self.textContainerInset.left
        location.y -= self.textContainerInset.top

        let characterIndex = self.layoutManager.characterIndex(
            for: location,
            in: self.textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        if characterIndex < self.textStorage.length,
           self.textStorage.attribute(
            NSAttributedString.Key.link,
            at: characterIndex,
            effectiveRange: nil
           ) != nil {
            return self
        }
        return nil
    }

    var animationTask: Task<Void, Never>?

    func startReadAnimation() async {
        self.animationTask?.cancel()

        self.animationTask = Task {
            let nsString = self.attributedText.string as NSString
            let substringRanges = nsString.getRangesOfSubstringsSeparatedBySpaces()
            let lookAheadCount = 5

            for index in -lookAheadCount..<substringRanges.count {
                guard !Task.isCancelled else { return }
                let updatedText = self.attributedText.mutableCopy()
                    as! NSMutableAttributedString
                let keyPoints: [CGFloat] = [1, 0.9, 0.7, 0.35, 0]

                for lookAheadIndex in 0...lookAheadCount {
                    guard let nextRange = substringRanges[
                        safe: index + lookAheadIndex
                    ] else { continue }
                    let alpha = lerp(
                        CGFloat(lookAheadIndex) / CGFloat(lookAheadCount),
                        keyPoints: keyPoints
                    )
                    updatedText.addAttribute(
                        .foregroundColor,
                        value: ThemeColor.white.color.withAlphaComponent(alpha),
                        range: nextRange
                    )
                }

                await withCheckedContinuation { continuation in
                    UIView.transition(
                        with: self,
                        duration: 0.1,
                        options: [.transitionCrossDissolve, .curveLinear]
                    ) {
                        self.attributedText = updatedText
                    } completion: { _ in
                        continuation.resume(returning: ())
                    }
                }
            }
            self.textColor = ThemeColor.white.color
        }

        await self.animationTask?.value
    }
}
