//
//  RecentReplyView.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/28/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat
import Combine
import Lottie

class RecentReplyView: CollectionViewManagerCell, ManageableCell {
    typealias ItemType = Message
    
    var currentItem: Message?
    
    let titleLabel = ThemeLabel(font: .regular)
    let messageContent = MessageContentView()
    
    let middleBubble = MessageBubbleView(orientation: .up, bubbleColor: .D1)
    let bottomBubble = MessageBubbleView(orientation: .up, bubbleColor: .D1)

    private var controller: MessageController?
    
    let animationView = AnimationView.with(animation: .loading)
    let label  = ThemeLabel(font: .regular)
    
    var subscriptions = Set<AnyCancellable>()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.contentView.addSubview(self.animationView)
        self.animationView.loopMode = .loop
        self.contentView.addSubview(self.label)
        self.label.alpha = 0.25
        self.label.setText("No replies")
        
        self.contentView.addSubview(self.bottomBubble)
        self.contentView.addSubview(self.middleBubble)
        self.contentView.addSubview(self.messageContent)
        self.messageContent.layoutState = .collapsed
        
        let bubbleColor = ThemeColor.D1.color
        self.messageContent.configureBackground(color: bubbleColor,
                                                textColor: ThemeColor.T3.color,
                                                brightness: 1.0,
                                                showBubbleTail: false,
                                                tailOrientation: .up)
        
        self.middleBubble.setBubbleColor(bubbleColor.withAlphaComponent(0.8), animated: false)
        self.middleBubble.tailLength = 0
        self.middleBubble.layer.masksToBounds = true
        self.middleBubble.layer.cornerRadius = Theme.cornerRadius
        
        self.bottomBubble.setBubbleColor(bubbleColor.withAlphaComponent(0.6), animated: false)
        self.bottomBubble.layer.masksToBounds = true
        self.bottomBubble.layer.cornerRadius = Theme.cornerRadius
        self.bottomBubble.tailLength = 0
        
        self.messageContent.isVisible = false
        self.middleBubble.isVisible = false
        self.bottomBubble.isVisible = false
        self.label.isVisible = false
    }
    
    func configure(with item: Message) {
        Task.onMainActorAsync {
            
            if self.controller?.message != item {
                self.controller = ChatClient.shared.messageController(cid: item.cid!, messageId: item.id)
                self.animationView.play()
                try? await self.controller?.loadPreviousReplies()
                self.subscribeToUpdates()
            } else {
                self.label.isVisible = true
            }
            
            guard !Task.isCancelled else { return }
            
            if let latest = self.controller?.replies.first {
                self.update(for: latest)
            } else {
                self.label.isVisible = true
                self.animationView.stop()
            }
        }
    }
    
    @MainActor
    private func update(for message: Message) {
        self.messageContent.configure(with: message)
        self.messageContent.isVisible = true
        self.middleBubble.isVisible = true
        self.bottomBubble.isVisible = true
        self.label.isVisible = false
        self.animationView.stop()
        self.layoutNow()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.label.setSize(withWidth: self.contentView.width)
        self.label.centerOnXAndY()
        
        self.animationView.size = CGSize(width: 18, height: 18)
        self.animationView.centerOnXAndY()
        
        let maxWidth = self.width - Theme.ContentOffset.xtraLong.value.doubled
        
        self.messageContent.width = maxWidth
        self.messageContent.height = MessageContentView.collapsedHeight
        self.messageContent.centerOnX()
        self.messageContent.pin(.top, offset: .custom(32))
        
        self.middleBubble.width = maxWidth * 0.8
        self.middleBubble.height = self.messageContent.height
        self.middleBubble.centerOnX()
        self.middleBubble.match(.bottom, to: .bottom, of: self.messageContent, offset: .standard)
        
        self.bottomBubble.width = maxWidth * 0.6
        self.bottomBubble.height = self.messageContent.height
        self.bottomBubble.centerOnX()
        self.bottomBubble.match(.bottom, to: .bottom, of: self.middleBubble, offset: .standard)
    }
    
    private func subscribeToUpdates() {
        
        self.subscriptions.forEach { cancellable in
            cancellable.cancel()
        }
        self.controller?
            .repliesChangesPublisher
            .mainSink { [unowned self] _ in
                guard let message = self.currentItem else { return }
                self.configure(with: message)
            }.store(in: &self.subscriptions)
    }
}
