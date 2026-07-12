//
//  SwipeableInputAccessoryView.swift
//  Jibber
//
//  Created by Martin Young on 12/6/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

@MainActor
protocol MessageSendingViewControllerType: UIViewController {
    func getCurrentMessageSequence() -> MessageSequence?
    func set(messageSequencePreparingToSend: MessageSequence?)
    func sendMessage(_ message: MessageSendable) async throws
}

@MainActor
protocol MessageSendingCollectionViewType: CollectionView {
    func getMessageDropZoneFrame(convertedTo view: UIView) -> CGRect
}

@MainActor
final class SwipeableInputAccessoryMessageSender: @MainActor SwipeableInputAccessoryViewControllerDelegate {

    unowned let viewController: MessageSendingViewControllerType
    unowned let collectionView: MessageSendingCollectionViewType
            
    private var contentContainer: UIView? {
        return self.collectionView.superview
    }

    init(viewController: MessageSendingViewControllerType, collectionView: MessageSendingCollectionViewType) {
        self.viewController = viewController
        self.collectionView = collectionView
    }

    // MARK: - SwipeableInputAccessoryViewDelegate

    func swipeableInputAccessoryDidBeginSwipe(_ controller: SwipeableInputAccessoryViewController) {
        // Set the drop zone frame on the swipe view so it knows where to gravitate the message toward.
        let overlayFrame = self.collectionView.getMessageDropZoneFrame(convertedTo: controller.view)
        controller.dropZoneFrame = overlayFrame
        
        self.collectionView.isUserInteractionEnabled = false

        guard let currentMessageSequence = self.viewController.getCurrentMessageSequence() else { return }

        self.viewController.set(messageSequencePreparingToSend: currentMessageSequence)
    }

    func swipeableInputAccessory(_ controller: SwipeableInputAccessoryViewController,
                                 triggeredSendFor sendable: MessageSendable,
                                 withPreviewFrame frame: CGRect) async -> Bool {

        // Ensure that the preview has been dragged far up enough to send.
        let dropZoneFrame = controller.dropZoneFrame
        let shouldSend = dropZoneFrame.bottom > frame.centerY

        guard shouldSend else { return false }

        do {
            try await self.viewController.sendMessage(sendable)
            return true
        } catch {
            await ToastScheduler.shared.schedule(toastType: .error(error))
            logError(error)
            return false
        }
    }

    func swipeableInputAccessoryDidFinishSwipe(_ controller: SwipeableInputAccessoryViewController) {
        self.collectionView.isUserInteractionEnabled = true
        self.viewController.set(messageSequencePreparingToSend: nil)
    }
}
