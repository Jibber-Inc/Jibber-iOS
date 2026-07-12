//
//  TranscriptTextView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/17/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Localization
import Speech
import Combine
import UIKit

/// A value-only representation of Speech framework output that can safely
/// cross from its callback queue to the main actor.
struct SpeechTranscriptionSnapshot: Sendable {
    struct Segment: Sendable {
        let location: Int
        let length: Int

        var range: NSRange {
            NSRange(location: self.location, length: self.length)
        }
    }

    let formattedString: String
    let segments: [Segment]

    init(result: SFSpeechRecognitionResult) {
        let transcription = result.bestTranscription
        self.formattedString = transcription.formattedString
        self.segments = transcription.segments.map { segment in
            Segment(location: segment.substringRange.location,
                    length: segment.substringRange.length)
        }
    }
}

class CaptionTextView: TextView {
    
    var cancellables = Set<AnyCancellable>()
    
    var placeholderText: String = "Add caption"
    
    init() {
        super.init(frame: .zero, font: .regular, textColor: .white, alignment: .left, textContainer: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.set(placeholder: "Add caption", alignment: .left)
        
        self.delegate = self
        
        self.setFont(.regular)
        self.textColor = ThemeColor.white.color.withAlphaComponent(0.8)
        
        self.isEditable = true
        self.isScrollEnabled = false
        self.isSelectable = true
        self.textAlignment = .left
        self.alpha = 0
        self.tintColor = ThemeColor.D6.color
        self.returnKeyType = .done
        
        let offset = Theme.ContentOffset.standard.value

        self.textContainerInset.left = offset
        self.textContainerInset.right = offset
        self.textContainerInset.top = offset
        self.textContainerInset.bottom = offset
        
        self.layer.masksToBounds = true
        self.layer.cornerRadius = Theme.innerCornerRadius
        
        self.backgroundColor = ThemeColor.B0.color.withAlphaComponent(0.6)
        
        self.$publishedText.mainSink { [unowned self] text in
            guard !self.placeholderText.isEmpty else { return }
            let color: ThemeColor = text.isEmpty ? .whiteWithAlpha : .clear
            let styleAttributes = StringStyle(font: .regular, color: color).attributes
            let string = NSAttributedString(string: self.placeholderText, attributes: styleAttributes)
            self.attributedPlaceholder = string
            self.layoutNow()
        }.store(in: &self.cancellables)
    }
    
    override func getSize(withMaxWidth maxWidth: CGFloat, maxHeight: CGFloat = CGFloat.infinity) -> CGSize {
        let maxWidth = clamp(maxWidth, min: 0)
        let horizontalPadding = self.contentInset.horizontal + self.textContainerInset.horizontal
        let verticalPadding = self.contentInset.vertical + self.textContainerInset.vertical

        // Get the max size available for the text, taking the textview's insets into account.
        var size: CGSize = self.getTextContentSize(withMaxWidth: maxWidth - horizontalPadding,
                                                   maxHeight: maxHeight - verticalPadding)
        
        let placeholderSize: CGSize = self.getPlaceholderContentSize(withMaxWidth: maxWidth - horizontalPadding,
                                                                     maxHeight: maxHeight - verticalPadding)
        let minWidth = clamp(placeholderSize.width + horizontalPadding + 4, min: 0) 
        let minHeight = placeholderSize.height + verticalPadding

        // Add back the spacing for the text container insets, but ensure we don't exceed the maximum.
        size.width += horizontalPadding
        size.width = clamp(size.width, minWidth, maxWidth)

        size.height += verticalPadding
        size.height = clamp(size.height, minHeight, maxHeight)

        return size
    }
    
    func animateCaption(text: String?) {

        if let text = text, !text.isEmpty {
            self.animationTask?.cancel()
            self.setTextColor(.clear)
            self.alpha = 0
            
            self.setText(text)
                    
            Task {
                async let fadeIn: () = UIView.awaitAnimation(with: .fast, animations: {
                    self.alpha = 1.0
                })
                async let textAnimation: () = self.startAnimation()
                let _: [()] = await [fadeIn, textAnimation]
            }
        } else if self.isEditable {
            UIView.animate(withDuration: Theme.animationDurationFast) {
                self.alpha = 1
                self.layoutNow()
            }
        }
    }

    var animationTask: Task<Void, Never>?
    
    func startAnimation() async {
        self.animationTask?.cancel()

        self.animationTask = Task {
            let nsString = self.attributedText.string as NSString
            let substringRanges: [NSRange] = nsString.getRangesOfSubstringsSeparatedBySpaces()

            let lookAheadCount = 5
            for index in -lookAheadCount..<substringRanges.count {
                guard !Task.isCancelled else { return }

                let updatedText = self.attributedText.mutableCopy() as! NSMutableAttributedString

                let keyPoints: [CGFloat] = [1, 0.9, 0.7, 0.35, 0]

                for i in 0...lookAheadCount {
                    guard let nextRange = substringRanges[safe: index + i] else { continue }

                    let alpha = lerp(CGFloat(i)/CGFloat(lookAheadCount), keyPoints: keyPoints)
                    updatedText.addAttribute(.foregroundColor,
                                             value: ThemeColor.white.color.withAlphaComponent(alpha),
                                             range: nextRange)

                }

                await withCheckedContinuation { continuation in
                    UIView.transition(with: self,
                                      duration: 0.1,
                                      options: [.transitionCrossDissolve, .curveLinear]) {
                        self.attributedText = updatedText
                    } completion: { completed in
                        continuation.resume(returning: ())
                    }
                }
            }

            self.textColor = ThemeColor.white.color
        }

        await self.animationTask?.value
    }
    
    func animateSpeech(snapshot: SpeechTranscriptionSnapshot?) {

        if let snapshot {
            self.animationTask?.cancel()
            self.setTextColor(.clear)
            self.alpha = 0
            
            self.setText(snapshot.formattedString)

            Task { @MainActor in
                UIView.animate(withDuration: Theme.animationDurationFast) {
                    self.alpha = 1.0
                }
                await self.startAnimation(with: snapshot.segments)
            }
        } else {
            UIView.animate(withDuration: Theme.animationDurationFast) {
                self.alpha = 1
            }
        }
    }
    
    func startAnimation(with segments: [SpeechTranscriptionSnapshot.Segment]) async {
        self.animationTask?.cancel()

        self.animationTask = Task {

            let keyPoints: [CGFloat] = [0.8, 0.7, 0.6, 0.35, 0]

            for index in -keyPoints.count..<segments.count {
                guard !Task.isCancelled else { return }

                let updatedText = self.attributedText.mutableCopy() as! NSMutableAttributedString

                for i in 0...keyPoints.count {
                    guard let nextSegment = segments[safe: index + i] else { continue }

                    let alpha = lerp(CGFloat(i)/CGFloat(keyPoints.count), keyPoints: keyPoints)
                    updatedText.addAttribute(.foregroundColor,
                                             value: ThemeColor.white.color.withAlphaComponent(alpha),
                                             range: nextSegment.range)

                }

                await withCheckedContinuation { continuation in
                    UIView.transition(with: self,
                                      duration: 0.1,
                                      options: [.transitionCrossDissolve, .curveLinear]) {
                        self.attributedText = updatedText
                    } completion: { completed in
                        continuation.resume(returning: ())
                    }
                }
            }

            self.textColor = ThemeColor.white.color.withAlphaComponent(0.8)
        }

        await self.animationTask?.value
    }
}

extension CaptionTextView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        return true
    }
}
