//
//  MessageCell.swift
//  Jibber
//
//  Created by Martin Young on 11/1/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

struct MessageDetailState: Equatable {
    var areDetailsFullyVisible: Bool = false
}

/// A cell for displaying individual messages, author and reactions.
class MessageCell: ConversationMessagePresentationCell {

    private struct AppliedLayoutState: Equatable {
        let brightness: CGFloat
        let detailAlpha: CGFloat
        let shouldShowDetailBar: Bool
    }

    private var message: Messageable?
    private var lastAppliedLayoutState: AppliedLayoutState?
    private var messageController: ParseMessageController?
    private var replyPreviewTask: Task<Void, Never>?
    private var replyPreviewToken: UUID?
    private var isCachedReplyPreviewRefreshPending = false
    
    private var footerView = MessageFooterView()
    
    var shouldShowDetailBar: Bool = true
    var shouldShowReplies: Bool = true {
        didSet {
            self.applyCapabilities()
        }
    }

    @Published private(set) var messageDetailState = MessageDetailState()
    private var conversationsManagerSubscription: AnyCancellable?
    private var messagingChangeSubscription: AnyCancellable?

    // Context menu
    private lazy var contextMenuDelegate = MessageContentContextMenuDelegate(content: self.content)
    private lazy var contextMenuInteraction = UIContextMenuInteraction(delegate: self.contextMenuDelegate)

    private var shouldPresentDetailFooter: Bool {
        self.shouldShowDetailBar
            && !self.capabilities.intersection([
                .replies,
                .expressions,
                .deliveryMetadata
            ]).isEmpty
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initializeViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initializeViews()
    }

    private func initializeViews() {
        self.content.bubbleView.addInteraction(self.contextMenuInteraction)
        
        self.timelineContentView.addSubview(self.footerView)
        
        self.footerView.expressionStackedView.didSelectExpression = { [unowned self] expression in
            guard let message = message else {
                return
            }
            self.content.delegate?.messageContent(self.content, didTapExpression: expression, forMessage: message)
        }
        
        self.footerView.replyButton.didTapViewReplies = { [unowned self] in
            guard let message = self.message else { return }
            self.content.delegate?.messageContent(self.content, didTapViewReplies: message)
        }
        
        self.footerView.replyButton.didSelectSuggestion = { [unowned self] text in
            self.addReply(with: text)
        }
        
        self.footerView.didTapViewReplies = { [unowned self] in
            guard let message = self.message else { return }
            self.content.delegate?.messageContent(self.content, didTapViewReplies: message)
        }
        
        self.footerView.expressionStackedView.addExpressionView.didSelect { [unowned self] in
            guard let message = self.message else { return }
            self.content.delegate?.messageContent(self.content, didTapAddExpressionForMessage: message)
        }

        self.conversationsManagerSubscription = ConversationsManager.shared.$activeConversation
            .removeDuplicates(by: { $0?.id == $1?.id })
            .mainSink { [unowned self] activeConversation in
                // Always run the visibility handler so switching away cancels
                // an in-flight consumption task. The handler itself gates any
                // new task to the currently active conversation.
                self.handleDetailVisibility(areDetailsFullyVisible: self.footerView.alpha == 1)
            }

        // Reply receipts arrive independently from their root message. Keep a
        // visible root footer current from the reconciled cache without giving
        // every reused preview controller its own global observer or network
        // synchronization loop.
        self.messagingChangeSubscription = NotificationCenter.default
            .publisher(for: .parseMessagingDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let message = self.message,
                      notification.affectsMessagingConversation(message.conversationId),
                      let controller = self.messageController else { return }
                self.scheduleCachedReplyPreviewRefresh(with: controller)
            }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard self.shouldPresentDetailFooter else {
            self.footerView.frame = CGRect(
                x: 0,
                y: self.timelineContentView.height,
                width: 0,
                height: 0
            )
            self.content.frame = self.timelineContentView.bounds
            self.shadowLayer.shadowPath = UIBezierPath(rect: self.content.bounds).cgPath
            return
        }

        self.footerView.width = self.timelineContentView.width - Theme.ContentOffset.long.value.doubled
        self.footerView.height = self.shouldShowReplies ? MessageFooterView.height : MessageFooterView.collapsedHeight
        self.footerView.centerOnX()
        self.footerView.pin(.bottom)
        
        self.content.width = self.timelineContentView.width
        self.content.pin(.top)
        self.content.expand(.bottom, to: self.footerView.top, offset: Theme.ContentOffset.long.value)

        self.shadowLayer.shadowPath = UIBezierPath(rect: self.content.bounds).cgPath
    }

    // MARK: Configuration

    func configure(
        with message: Messageable,
        capabilities: ConversationCapabilities = .production
    ) {
        super.configure(
            with: ConversationTimelineEntry(message: message),
            capabilities: capabilities
        )
    }

    override func didConfigure(
        with message: Messageable,
        capabilitiesChanged: Bool
    ) {

        let isDifferentMessage = self.message?.id != message.id
        if isDifferentMessage {
            self.messageTasks.cancelAndRemoveAll()
            self.messageDetailTasks.cancelAndRemoveAll()
            self.lastAppliedLayoutState = nil
            self.messageController = nil
            self.replyPreviewTask?.cancel()
            self.replyPreviewTask = nil
            self.replyPreviewToken = nil
            self.isCachedReplyPreviewRefreshPending = false
        }

        let previewMessage = self.prepareReplyPreview(for: message)
        let hasPreviewPresentationChanges = self.hasPresentationChanges(
            from: self.message,
            to: previewMessage
        )
        super.didConfigure(
            with: previewMessage,
            capabilitiesChanged: capabilitiesChanged
        )
        if hasPreviewPresentationChanges || capabilitiesChanged {
            self.footerView.configure(for: previewMessage)
        }

        self.message = previewMessage
        self.applyCapabilities()
    }

    override func hasPresentationChanges(
        from previousMessage: Messageable?,
        to message: Messageable
    ) -> Bool {
        guard let previousMessage = previousMessage as? ParseMessage,
              let message = message as? ParseMessage else {
            // Local onboarding messages can replace their guide/avatar while
            // retaining stable IDs and copy, so they must be re-presented.
            return true
        }
        return previousMessage != message
    }

    override func applyTimelinePresentation(
        brightness: CGFloat,
        detailAlpha: CGFloat
    ) {
        let shouldPresentDetail = self.shouldPresentDetailFooter
        let layoutState = AppliedLayoutState(
            brightness: brightness,
            detailAlpha: detailAlpha,
            shouldShowDetailBar: shouldPresentDetail
        )
        guard layoutState != self.lastAppliedLayoutState else { return }

        let previousLayoutState = self.lastAppliedLayoutState
        self.lastAppliedLayoutState = layoutState

        super.applyTimelinePresentation(
            brightness: brightness,
            detailAlpha: detailAlpha
        )

        self.footerView.alpha = shouldPresentDetail ? detailAlpha : 0

        // Hide the emotions view if the cell is scrolled out of focus.
        if detailAlpha < 0.5,
           previousLayoutState == nil || (previousLayoutState?.detailAlpha ?? 0) >= 0.5 {
            self.content.setEmotions(areShown: false, animated: true)
        }

        let areDetailsFullyVisible = detailAlpha == 1 && shouldPresentDetail

        let wereDetailsFullyVisible = previousLayoutState?.detailAlpha == 1
            && previousLayoutState?.shouldShowDetailBar == true
        if previousLayoutState == nil || areDetailsFullyVisible != wereDetailsFullyVisible {
            if areDetailsFullyVisible {
                self.playAllVideo()
            } else {
                self.pauseAllVideo()
            }

            self.messageDetailState = MessageDetailState(
                areDetailsFullyVisible: areDetailsFullyVisible
            )
            self.handleDetailVisibility(areDetailsFullyVisible: areDetailsFullyVisible)
        }
    }

    private func applyCapabilities() {
        let supportsReplies = self.capabilities.contains(.replies) && self.shouldShowReplies
        let supportsExpressions = self.capabilities.contains(.expressions)
        let supportsDeliveryMetadata = self.capabilities.contains(.deliveryMetadata)

        let hasContextMenu = self.content.bubbleView.interactions.contains { interaction in
            interaction === self.contextMenuInteraction
        }
        if self.capabilities.contains(.contextMenus), !hasContextMenu {
            self.content.bubbleView.addInteraction(self.contextMenuInteraction)
        } else if !self.capabilities.contains(.contextMenus), hasContextMenu {
            self.content.bubbleView.removeInteraction(self.contextMenuInteraction)
        }
        self.applyMessageCapabilities()

        self.footerView.replySummary.isVisible = supportsReplies
        self.footerView.replyButton.isVisible = supportsReplies && self.message?.isReply == false
        self.footerView.expressionStackedView.isVisible = supportsExpressions
        self.footerView.statusLabel.isVisible = supportsDeliveryMetadata
        self.footerView.isVisible = self.shouldShowDetailBar
            && (supportsReplies || supportsExpressions || supportsDeliveryMetadata)
        self.setNeedsLayout()
    }
    
    private func pauseAllVideo() {
        self.content.authorView.expressionVideoView.shouldPlay = false
        self.footerView.expressionStackedView.subviews.forEach { view in
            if let personView = view as? PersonGradientView {
                personView.expressionVideoView.shouldPlay = false
            }
        }
    }
    
    private func playAllVideo() {
        self.content.authorView.expressionVideoView.shouldPlay = true
        self.footerView.expressionStackedView.subviews.forEach { view in
            if let personView = view as? PersonGradientView {
                personView.expressionVideoView.shouldPlay = true
            }
        }
    }

    private var messageTasks = TaskPool()

    private func prepareReplyPreview(for message: Messageable) -> Messageable {
        guard self.capabilities.contains(.replies),
              let message = message as? ParseMessage else {
            self.replyPreviewTask?.cancel()
            self.replyPreviewTask = nil
            self.replyPreviewToken = nil
            self.isCachedReplyPreviewRefreshPending = false
            self.messageController = nil
            return message
        }

        let existingPreviewController = self.messageController.flatMap { controller in
            controller.messageId == message.id ? controller : nil
        }
        let hasKnownReplies = message.totalReplyCount > 0
            || (existingPreviewController?.message?.totalReplyCount ?? 0) > 0
        guard hasKnownReplies else {
            self.replyPreviewTask?.cancel()
            self.replyPreviewTask = nil
            self.replyPreviewToken = nil
            self.isCachedReplyPreviewRefreshPending = false
            self.messageController = nil
            return message
        }

        let controller: ParseMessageController
        if let existingController = existingPreviewController {
            existingController.updateReplyPreviewRoot(with: message)
            controller = existingController
        } else {
            self.replyPreviewTask?.cancel()
            self.replyPreviewTask = nil
            self.replyPreviewToken = nil
            self.isCachedReplyPreviewRefreshPending = false
            guard let newController = ParseMessageController.replyPreviewController(for: message) else {
                self.messageController = nil
                return message
            }
            controller = newController
            self.messageController = newController
        }

        if self.replyPreviewTask == nil {
            self.startReplyPreviewRefresh(with: controller)
        }
        return controller.message ?? message
    }

    private func startReplyPreviewRefresh(with controller: ParseMessageController) {
        let token = UUID()
        self.replyPreviewToken = token
        self.replyPreviewTask = Task { @MainActor [weak self, weak controller] in
            defer {
                if self?.replyPreviewToken == token {
                    self?.replyPreviewTask = nil
                    self?.replyPreviewToken = nil
                    if let self,
                       self.isCachedReplyPreviewRefreshPending,
                       let controller = self.messageController {
                        self.startCachedReplyPreviewRefresh(with: controller)
                    }
                }
            }
            do {
                try await controller?.synchronizeReplyPreview()
            } catch is CancellationError {
                return
            } catch {
                logError(error)
            }
            self?.refreshFooter(from: controller)
        }
    }

    private func scheduleCachedReplyPreviewRefresh(with controller: ParseMessageController) {
        self.isCachedReplyPreviewRefreshPending = true
        guard self.replyPreviewTask == nil else { return }
        self.startCachedReplyPreviewRefresh(with: controller)
    }

    private func startCachedReplyPreviewRefresh(with controller: ParseMessageController) {
        let token = UUID()
        self.replyPreviewToken = token
        self.replyPreviewTask = Task { @MainActor [weak self, weak controller] in
            defer {
                if self?.replyPreviewToken == token {
                    self?.replyPreviewTask = nil
                    self?.replyPreviewToken = nil
                }
            }
            while self?.isCachedReplyPreviewRefreshPending == true, !Task.isCancelled {
                self?.isCachedReplyPreviewRefreshPending = false
                do {
                    try await controller?.refreshCachedReplyPreview()
                } catch is CancellationError {
                    return
                } catch {
                    logError(error)
                }
                self?.refreshFooter(from: controller)
            }
        }
    }

    private func refreshFooter(from controller: ParseMessageController?) {
        guard controller === self.messageController,
              let message = controller?.message else { return }
        self.message = message
        if self.shouldShowDetailBar {
            self.footerView.configure(for: message)
            self.applyCapabilities()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.pauseAllVideo()
        self.content.authorView.displayable = nil
        self.content.imageView.displayable = nil
        self.content.emotionCollectionView.setEmotionsCounts([:], animated: false)
        self.content.setEmotions(areShown: false, animated: false)
        self.message = nil
        self.lastAppliedLayoutState = nil
        self.messageDetailState = MessageDetailState()
        self.messageController = nil
        self.replyPreviewTask?.cancel()
        self.replyPreviewTask = nil
        self.replyPreviewToken = nil
        self.isCachedReplyPreviewRefreshPending = false
        self.messageTasks.cancelAndRemoveAll()
        self.messageDetailTasks.cancelAndRemoveAll()
    }

    // MARK: - Message Detail Tasks

    /// A pool of tasks related to updating the message details.
    private var messageDetailTasks = TaskPool()

    /// Handles changes to the message detail view's visibility.
    private func handleDetailVisibility(areDetailsFullyVisible: Bool) {
        // If the detail visibility changes for a message, we always want to cancel its tasks.
        self.messageDetailTasks.cancelAndRemoveAll()

        guard self.shouldPresentDetailFooter,
              let messageable = self.message as? ParseMessage,
              let cid = try? ConversationId(cid: messageable.conversationId) else { return }

        guard areDetailsFullyVisible else { return }

        // Don't consume messages unless they're a part of the active conversation.
        if ConversationsManager.shared.activeConversation?.cid == cid {
            self.startConsumptionTaskIfNeeded(for: messageable)
        }
    }

    /// If necessary for the message, starts a task that sets the delivery status to reading, then consumes the message after a delay.
    private func startConsumptionTaskIfNeeded(for messageable: ParseMessage) {
        guard messageable.canBeConsumed else { return }

        Task {
            guard !Task.isCancelled else { return }

            await self.content.playReadAnimations()
            
            UIView.animate(withDuration: Theme.animationDurationFast, delay: 0.1) {
                self.shadowLayer.opacity = 0
            }

            guard !Task.isCancelled else { return }

            await messageable.setToConsumed()
        }.add(to: self.messageDetailTasks)
    }
    
    private func addReply(with text: String) {
        guard self.capabilities.contains(.replies),
              let msg = self.message as? ParseMessage,
              let controller = ParseMessageController.controller(for: msg) else { return }
        
        Task {
            do {
                let object = SendableObject(kind: .text(text),
                                            deliveryType: msg.deliveryType,
                                            expression: nil)
                try await controller.createNewReply(with: object)

                AnalyticsManager.shared.trackEvent(type: .suggestionSelected, properties: ["value": text])
            } catch {
                await ToastScheduler.shared.schedule(toastType: .error(error))
                logError(error)
            }
        }.add(to: self.messageTasks)
    }
    
    // MARK: - Touch Handling

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Only respond to touches that are in the visible content areas.
        let contentPoint = self.convert(point, to: self.content)
        let footerPoint = self.convert(point, to: self.footerView)

        return self.content.point(inside: contentPoint, with: event)
        || self.footerView.point(inside: footerPoint, with: event)
    }
}
