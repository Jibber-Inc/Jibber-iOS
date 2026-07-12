//
//  SwipeInputPanGestureRecognizer.swift
//  Jibber
//
//  Created by Martin Young on 1/26/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie

/// Handles pan gesture input on behalf of the swipeable input accessory.
@MainActor
class SwipeInputPanGestureHandler {

    let viewController: SwipeableInputAccessoryViewController
    var inputView: SwipeableInputAccessoryView {
        return self.viewController.swipeInputView
    }

    init(viewController: SwipeableInputAccessoryViewController) {
        self.viewController = viewController
    }

    /// An object to give the user touch feedback when performing certain actions.
    private var impactFeedback = UIImpactFeedbackGenerator(style: .rigid)
    private var previewView: PreviewMessageView?
    /// The center point of the preview view when the pan started.
    private var initialPreviewCenter: CGPoint?
    /// How far the preview view can be dragged left or right.
    private let maxXOffset: CGFloat = 20
    /// If true, the preview view is currently in the drop zone.
    private var isPreviewInDropZone = false
    /// The distance the user needs to drag in order to send a message at the highest delivery priority
    private let totalDragDistance: CGFloat = 160

    func handle(pan: UIPanGestureRecognizer) {
        guard self.shouldHandlePan() else { return }

        let panOffset = pan.translation(in: nil)

        switch pan.state {
        case .possible:
            break
        case .began:
            self.handlePanBegan()
        case .changed:
            self.handlePanChanged(withOffset: panOffset)
        case .ended:
            self.handlePanEnded(withOffset: panOffset)
        case .cancelled, .failed:
            self.handlePanFailed()
        @unknown default:
            break
        }
    }

    private func shouldHandlePan() -> Bool {
        guard ConversationsManager.shared.activeConversation.exists else { return false }
        // Only handle pans if the user has input a sendable message.
        let object = SendableObject(kind: self.viewController.currentMessageKind,
                                    deliveryType: .respectful,
                                    expression: nil,
                                    previousMessage: self.viewController.editableMessage)
        return object.isSendable
    }

    private func handlePanBegan() {
        let object = SendableObject(kind: self.viewController.currentMessageKind,
                                    deliveryType: .respectful,
                                    expression: nil,
                                    previousMessage: self.viewController.editableMessage)
        self.viewController.sendable = object

        // Hide the input area. The preview view will take its place during the pan.
        self.inputView.inputContainerView.alpha = 0

        // Stop any swipe hint animations if they're playing.
        self.viewController.updateSwipeHint(shouldPlay: false)

        // Initialize the preview view for the user to drag up the screen.
        self.previewView = PreviewMessageView(orientation: .down,
                                              bubbleColor: object.deliveryType.color.color)
        self.previewView?.frame = self.inputView.inputContainerView.frame
        self.previewView?.messageKind = self.viewController.currentMessageKind
        self.previewView?.showShadow(withOffset: 8)
        self.inputView.addSubview(self.previewView!)

        self.initialPreviewCenter = self.previewView?.center

        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.inputView.addView.alpha = 0.0
        }
        
        self.animatePreviewScale(shouldScale: true)
        
        self.viewController.delegate?.swipeableInputAccessoryDidBeginSwipe(self.viewController)
    }
    
    private func animatePreviewScale(shouldScale: Bool, completion: CompletionOptional = nil) {
        let transform: CGAffineTransform = shouldScale ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
        UIView.animate(withDuration: Theme.animationDurationStandard,
                       delay: 0.0,
                       usingSpringWithDamping: 0.5,
                       initialSpringVelocity: 5, options: .curveEaseInOut) {
            self.previewView?.transform = transform
        } completion: { _ in
            completion?()
        }
    }

    private func handlePanChanged(withOffset panOffset: CGPoint) {
        self.updatePreviewViewPosition(withOffset: panOffset)
    }

    private func handlePanEnded(withOffset panOffset: CGPoint) {
        self.updatePreviewViewPosition(withOffset: panOffset)

        Task.onMainActorAsync { [weak self] in
            var sendableWasSent = false

            if let `self` = self,
               let sendable = self.viewController.sendable,
               let previewView = self.previewView,
               let delegate = self.viewController.delegate {

                sendableWasSent = await delegate.swipeableInputAccessory(self.viewController,
                                                                         triggeredSendFor: sendable,
                                                                         withPreviewFrame: previewView.frame)
            }

            guard let self else { return }

            self.resetPreviewAndInputViews(didSend: sendableWasSent)

            self.viewController.delegate?.swipeableInputAccessoryDidFinishSwipe(self.viewController)
        }
    }

    private func handlePanFailed() {
        self.inputView.inputContainerView.alpha = 1
        self.previewView?.removeFromSuperview()
        self.viewController.delegate?.swipeableInputAccessoryDidFinishSwipe(self.viewController)
    }

    /// Updates the position of the preview view based on the provided pan gesture offset. This function ensures that preview view's origin
    /// is kept within bounds defined by max X and Y offset.
    private func updatePreviewViewPosition(withOffset panOffset: CGPoint) {
        guard let initialCenter = self.initialPreviewCenter,
              let previewView = self.previewView else { return }

        let panResult = self.getYOffsetAndDeliveryType(withPanOffset: panOffset.y)

        let offsetX = clamp(panOffset.x, -self.maxXOffset, self.maxXOffset)
        let offsetY = panResult.offset
        let previewCenter = initialCenter + CGPoint(x: offsetX, y: offsetY)
        previewView.center = previewCenter

        let dropZoneCenter = self.viewController.dropZoneFrame.center

        // Provide haptic and visual feedback when the message is ready to send.
        let distanceToDropZone = CGVector(startPoint: previewCenter, endPoint: dropZoneCenter).magnitude
        if distanceToDropZone < self.viewController.dropZoneFrame.height * 0.5 {
            if !self.isPreviewInDropZone {
                self.animatePreviewScale(shouldScale: false)
                previewView.setBubbleColor(ThemeColor.B6.color, animated: true)
                previewView.textView.setTextColor(.white)
            }
            self.isPreviewInDropZone = true

            // Update the delivery type
            self.viewController.sendable?.deliveryType = panResult.deliveryType

            if previewView.deliveryType != panResult.deliveryType {
                previewView.deliveryType = panResult.deliveryType
                
                switch panResult.deliveryType {
                case .timeSensitive:
                    self.impactFeedback.impactOccurred(intensity: 1.0)
                case .conversational:
                    self.impactFeedback.impactOccurred(intensity: 0.8)
                case .respectful:
                    self.impactFeedback.impactOccurred(intensity: 0.6)
                }
            }
        } else {
            if self.isPreviewInDropZone {
                self.animatePreviewScale(shouldScale: true)
                previewView.setBubbleColor(ThemeColor.B1.color, animated: true)
                // Apple bug where the trait collection for all subviews is dark, even though it should be light.
                // So we have to access the window to get the correct trait.
                if let window = UIWindow.topWindow(), window.traitCollection.userInterfaceStyle == .light {
                    previewView.textView.setTextColor(.B0)
                } else {
                    previewView.textView.setTextColor(.white)
                }
            }
            self.isPreviewInDropZone = false

            // If the message is out of the drop zone, reset its delivery type back to respectful.
            self.viewController.sendable?.deliveryType = .respectful
            previewView.deliveryType = nil
        }
    }

    /// Get the yOffset that the preview view should have based up on the pan offset.
    /// Also returns the delivery type that corresponds to that offset.
    private func getYOffsetAndDeliveryType(withPanOffset panOffset: CGFloat)
    -> (offset: CGFloat, deliveryType: MessageDeliveryType) {

        guard let initialPreviewCenter = self.initialPreviewCenter else {
            return (panOffset, .respectful)
        }

        // Get the normalized drag distance, then adjust it so that it "gravitates" to three distinct spots.
        let normalized = -panOffset/self.totalDragDistance
        let adjustedNormalized = lerp(normalized, keyPoints: [0, 0.11, 0.22,    // No send
                                                              0.34, 0.35, 0.37, // Send with delivery mode low
                                                              0.56, 0.58, 0.59, // Send with delivery mode med
                                                              0.77, 0.78, 0.8])   // Send with delivery mode high

        let deliveryType: MessageDeliveryType
        switch adjustedNormalized {
        case 0..<0.56:
            deliveryType = .respectful
        case 0.56..<0.77:
            deliveryType = .conversational
        default:
            deliveryType = .timeSensitive
        }

        let dropZoneFrame = self.viewController.dropZoneFrame
        let firstCheckpoint = initialPreviewCenter.y - dropZoneFrame.bottom
        let secondCheckpoint = initialPreviewCenter.y - dropZoneFrame.centerY
        // Subtract 10 so it stays within the dropzone
        let thirdCheckpoint = initialPreviewCenter.y - dropZoneFrame.top - 10

        let finalOffset = lerp(adjustedNormalized,
                               keyPoints: [0, firstCheckpoint, secondCheckpoint, thirdCheckpoint])

        // Flip the sign of the offset because the preview view is swiped up,
        // which is in the negative direction.
        return (-finalOffset, deliveryType)
    }

    private func resetPreviewAndInputViews(didSend: Bool) {
        if didSend {
            var value: Int = UserDefaultsManager.getInt(for: .numberOfSwipeHints)
            if value < 3 {
                value += 1
                UserDefaultsManager.update(key: .numberOfSwipeHints, with: value)
            }
            
            self.impactFeedback.impactOccurred()
            self.animatePreviewScale(shouldScale: false) { [unowned self] in
                UIView.animate(withDuration: Theme.animationDurationStandard) {
                    self.previewView?.alpha = 0
                } completion: { completed in
                    self.previewView?.removeFromSuperview()
                    self.viewController.resetInputViews()
                }
            }
        } else {
            // If the user didn't swipe far enough to send a message, animate the preview view back
            // to where it started, then reveal the text view to allow for input again.
            self.inputView.inputContainerView.layer.shadowOpacity = 0.0
            UIView.animate(withDuration: Theme.animationDurationFast) {
                guard let initialOrigin = self.initialPreviewCenter else { return }
                self.previewView?.center = initialOrigin
                self.previewView?.transform = .identity
            } completion: { completed in
                UIView.animate(withDuration: Theme.animationDurationFast) {
                    self.inputView.inputContainerView.alpha = 1
                } completion: { completed in
                    self.inputView.inputContainerView.layer.shadowOpacity = 0.3
                    self.previewView?.removeFromSuperview()
                }
            }
        }

        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.inputView.addView.alpha = 1.0
        }
    }
}
