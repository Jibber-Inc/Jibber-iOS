//
//  ConversationContentView.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/22/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ScrollCounter
import Combine

class ConversationContentView: BaseView {
    
    let titleLabel = ThemeLabel(font: .regular)
    let messageContent = MessageContentView()
    
    let rightLabel = NumberScrollCounter(value: 0,
                                         scrollDuration: Theme.animationDurationSlow,
                                         decimalPlaces: 0,
                                         prefix: "Unread: ",
                                         suffix: nil,
                                         seperator: "",
                                         seperatorSpacing: 0,
                                         font: FontType.small.font,
                                         textColor: ThemeColor.white.color,
                                         animateInitialValue: true,
                                         gradientColor: nil,
                                         gradientStop: nil)
    let lineView = BaseView()
    
    private let stackedAvatarView = StackedPersonView()
    
    // Context menu
    private lazy var contextMenuDelegate = MessageContentContextMenuDelegate(content: self.messageContent)
    
    private(set) var conversationController: ParseConversationController?
    var subscriptions = Set<AnyCancellable>()
    private var configureTask: Task<Void, Never>?
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        let contextMenuInteraction = UIContextMenuInteraction(delegate: self.contextMenuDelegate)
        self.messageContent.bubbleView.addInteraction(contextMenuInteraction)
        // Ignore taps on any of the messages contents.
        self.messageContent.mainContentArea.isUserInteractionEnabled = false
        
        self.addSubview(self.lineView)
        self.lineView.set(backgroundColor: .white)
        self.lineView.alpha = 0.1
        
        self.addSubview(self.titleLabel)
        self.titleLabel.textAlignment = .left
        
        self.addSubview(self.messageContent)
        self.messageContent.layoutState = .collapsed
        
        self.addSubview(self.rightLabel)
        
        let bubbleColor = ThemeColor.B1.color
        self.messageContent.configureBackground(color: bubbleColor,
                                                textColor: ThemeColor.white.color,
                                                brightness: 1.0,
                                                showBubbleTail: false,
                                                tailOrientation: .up)
        
        self.addSubview(self.stackedAvatarView)
        self.stackedAvatarView.max = 5
    }
    
    func configure(with item: String) {
        self.configureTask?.cancel()
        self.configureTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let controller: ParseConversationController
            if let current = self.conversationController,
               current.conversationID.rawValue == item {
                controller = current
            } else {
                controller = ParseConversationController(
                    conversationID: item,
                    automaticallySynchronize: false
                )
                self.conversationController = controller
            }

            do {
                try await controller.synchronize(pageSize: 1)
            } catch {
                logError(error)
            }

            guard !Task.isCancelled,
                  self.conversationController === controller else { return }
            self.subscribeToUpdates()
            self.refreshVisibleState()
        }
    }
    
    private func setNumberOfUnread(value: Int) {
        let new = Float(value)
        guard new != self.rightLabel.currentValue else { return }
        self.rightLabel.setValue(new, animated: true)
    }
    
    @MainActor
    private func update(for message: ParseMessage) {
        self.messageContent.configure(with: message)
        
        let title = self.conversationController?.conversation?.title ?? "Untitled"
        self.titleLabel.setTextColor(.whiteWithAlpha)
        self.titleLabel.setText(title)
        
        self.layoutNow()
    }
    
    private func subscribeToUpdates() {
        self.subscriptions.forEach { cancellable in
            cancellable.cancel()
        }
        
        self.conversationController?
            .membersChangesPublisher
            .mainSink(receiveValue: { [weak self] _ in
                self?.refreshVisibleState()
            }).store(in: &self.subscriptions)

        self.conversationController?
            .conversationChangePublisher
            .mainSink(receiveValue: { [weak self] _ in
                self?.refreshVisibleState()
            }).store(in: &self.subscriptions)

        self.conversationController?
            .messagesChangesPublisher
            .mainSink { [weak self] _ in
                self?.refreshVisibleState()
            }.store(in: &self.subscriptions)
    }

    @MainActor
    private func refreshVisibleState() {
        guard let conversation = self.conversationController?.conversation else { return }

        let members = conversation.lastActiveMembers.filter {
            $0.personId != User.current()?.objectId
        }
        self.stackedAvatarView.configure(with: members)
        self.setNumberOfUnread(value: conversation.totalUnread)

        if let latest = conversation.latestMessages.first(where: { !$0.isDeleted }) {
            self.update(for: latest)
        } else {
            logDebug("No messages in conversation")
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let maxWidth = self.width
        
        self.messageContent.width = maxWidth
        self.messageContent.height = MessageContentView.collapsedHeight
        self.messageContent.centerOnXAndY()
        
        self.titleLabel.setSize(withWidth: self.width)
        self.titleLabel.match(.bottom, to: .top, of: self.messageContent, offset: .negative(.standard))
        self.titleLabel.match(.left, to: .left, of: self.messageContent)
        
        self.stackedAvatarView.match(.right, to: .right, of: self.messageContent)
        self.stackedAvatarView.centerY = self.titleLabel.centerY
        
        self.rightLabel.sizeToFit()
        self.rightLabel.pin(.bottom, offset: .standard)
        self.rightLabel.match(.right, to: .right, of: self.messageContent)
        
        self.lineView.height = 1
        self.lineView.expandToSuperviewWidth()
        self.lineView.pin(.bottom)
    }
}
