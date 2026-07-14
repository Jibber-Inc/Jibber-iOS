//
//  MessageDeliveryTypeMenuDelegate.swift
//  Jibber
//
//  Created by Martin Young on 3/23/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import KeyboardManager
import ParseCore

class MessageContentContextMenuDelegate: NSObject, UIContextMenuInteractionDelegate {

    unowned let content: MessageContentView

    init(content: MessageContentView) {
        self.content = content
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {

        return UIContextMenuConfiguration(identifier: nil) { [unowned self] () -> UIViewController? in
            guard let message = self.content.message else { return nil }
            return MessagePreviewViewController(with: message)
        } actionProvider: { [unowned self] (suggestions) -> UIMenu? in
            return self.makeContextMenu()
        }
    }

    private func makeContextMenu() -> UIMenu {
        guard let message = self.content.message else { return UIMenu() }

        let neverMind = UIAction(title: "Never Mind", image: ImageSymbol.noSign.image) { action in }

        let confirmDelete = UIAction(title: "Confirm",
                                     image: ImageSymbol.trash.image,
                                     attributes: .destructive) { action in
            Task { @MainActor in
                let controller = ParseMessageController(
                    conversationID: message.conversationId,
                    messageID: message.id,
                    automaticallySynchronize: false
                )
                do {
                    try await controller.synchronize()
                    try await controller.deleteMessage()
                } catch {
                    await ToastScheduler.shared.schedule(toastType: .error(error))
                }
            }
        }

        let deleteMenu = UIMenu(title: "Delete",
                                image: ImageSymbol.trash.image,
                                options: .destructive,
                                children: [confirmDelete, neverMind])

        let viewReplies = UIAction(title: "View Thread") { [unowned self] action in
            self.content.delegate?.messageContent(self.content, didTapViewReplies: message)
        }

        let edit = UIAction(title: "Edit",
                            image: ImageSymbol.pencil.image) { [unowned self] action in
            self.content.delegate?.messageContent(self.content, didTapEditMessage: message)
        }

        let read = UIAction(title: "Set to read",
                            image: ImageSymbol.eyeglasses.image) { [unowned self] action in
            self.setToRead()
        }

        let unread = UIAction(title: "Set to unread",
                              image: ImageSymbol.eyeglasses.image) { [unowned self] action in
            self.setToUnread()
        }

        var menuElements: [UIMenuElement] = []

        if !isRelease, message.isFromCurrentUser {
            menuElements.append(deleteMenu)
        }

        if !isRelease, message.isFromCurrentUser {
            menuElements.append(edit)
        }

        if message.isConsumedByMe {
            menuElements.append(unread)
        } else if message.canBeConsumed {
            menuElements.append(read)
        }

        if message.parentMessageId.isNil {
            menuElements.append(self.addReplyMenu())
            menuElements.append(viewReplies)
        }

        return UIMenu.init(title: "From: \(message.person?.fullName ?? "Unkown")",
                           image: nil,
                           identifier: nil,
                           options: [],
                           children: menuElements)
    }
    
    private func addReplyMenu() -> UIMenu {
        
        var elements: [UIMenuElement] = []
        
        SuggestedReply.allCases.reversed().forEach { suggestion in
            
            if suggestion == .emoji {
                let reactionElements: [UIMenuElement] = suggestion.emojiReactions.compactMap { emoji in
                    return UIAction(title: emoji, image: User.current()?.image) { [unowned self] _ in
                        self.addReply(with: emoji)
                    }
                }
                let reactionMenu = UIMenu(title: suggestion.text,
                                          image: suggestion.image,
                                          children: reactionElements)
                elements.append(reactionMenu)
                
            } else {
                let action = UIAction(title: suggestion.text, image: suggestion.image) { [unowned self] _ in
                    self.addReply(with: suggestion.text)
                }
                elements.append(action)
            }
        }

        return UIMenu(title: "Reply", image: ImageSymbol.arrowTurnUpLeft.image, children: elements)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return nil
    }

    private weak var firstResponderBeforeDisplay: UIResponder?
    private weak var inputHandlerBeforeDisplay: InputHandlerViewContoller?

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                animator: UIContextMenuInteractionAnimating?) {

        self.firstResponderBeforeDisplay = UIResponder.firstResponder
        self.inputHandlerBeforeDisplay = self.firstResponderBeforeDisplay?.inputHandlerViewController
    }
        
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                willEndFor configuration: UIContextMenuConfiguration,
                                animator: UIContextMenuInteractionAnimating?) {

        // HACK: The input handler has problems becoming first responder again after the context menu
        // disappears. The text view also becomes unresponsive. To get around this, reset the responder
        // status on the input handler.
        self.inputHandlerBeforeDisplay?.resignFirstResponder()
        self.inputHandlerBeforeDisplay?.becomeFirstResponder()

        self.firstResponderBeforeDisplay?.becomeFirstResponder()
    }

    // MARK: - Message Consumption

    func setToRead() {
        guard let msg = self.content.message, msg.canBeConsumed else { return }
        Task {
            await msg.setToConsumed()
        }
    }

    func setToUnread() {
        guard let msg = self.content.message, msg.isConsumedByMe else { return }
        Task {
            do {
                try await msg.setToUnconsumed()
            } catch {
                logError(error)
            }
        }
    }
    
    private func addReply(with text: String) {
        guard let msg = self.content.message else { return }
        
        Task { @MainActor in
            do {
                let controller = ParseMessageController(
                    conversationID: msg.conversationId,
                    messageID: msg.id,
                    automaticallySynchronize: false
                )
                try await controller.synchronize()
                let object = SendableObject(kind: .text(text),
                                            deliveryType: msg.deliveryType,
                                            expression: nil)
                try await controller.createNewReply(with: object)
                AnalyticsManager.shared.trackEvent(
                    type: .suggestionSelected,
                    properties: ["value": text]
                )
            } catch {
                await ToastScheduler.shared.schedule(toastType: .error(error))
            }
        }
    }
}

fileprivate extension UIResponder {

    /// Returns the nearest input handler view controller in the responder chain that has an input accessory view or input accessory VC.
    var inputHandlerViewController: InputHandlerViewContoller? {
        if let vc = self as? InputHandlerViewContoller {
            return vc
        }

        return self.next?.inputHandlerViewController
    }
}
