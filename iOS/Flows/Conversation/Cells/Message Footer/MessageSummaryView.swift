//
//  ReplyCountView.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/30/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class MessageSummaryView: BaseView {

    private var messageID: String?
    let replyView = MessagePreview()
    let badgeView = RepliesBadgeView()
        
    private var replyCount = 0
    private var totalUnreadReplyCount: Int = 0
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.replyView)
        self.addSubview(self.badgeView)
    }
    
    func configure(for message: Messageable) {
        guard let parseMessage = message as? ParseMessage else { return }

        if self.messageID == parseMessage.id,
            self.replyCount == parseMessage.replyCount,
            self.totalUnreadReplyCount == parseMessage.totalUnreadReplyCount {
            return
        }

        self.messageID = parseMessage.id
        self.replyCount = parseMessage.replyCount
        self.totalUnreadReplyCount = parseMessage.totalUnreadReplyCount

        if let reply = parseMessage.recentReplies.first {
            self.replyView.isVisible = true
            self.replyView.configure(with: reply)
        } else {
            self.replyView.isVisible = false
        }

        self.badgeView.configure(with: parseMessage)

        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.alpha = parseMessage.recentReplies.isEmpty ? 0.0 : 1.0
            self.layoutNow()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.replyView.expandToSuperviewSize()
        
        self.badgeView.pin(.top, offset: .negative(.custom(4)))
        self.badgeView.pin(.right, offset: .negative(.custom(4)))
    }
}
