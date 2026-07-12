//
//  CommentsBadgeView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/19/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import UIKit

class CommentsLabel: ThemeLabel {
    
    #if IOS
    private var controller: MessageSequenceController?
    private var subscriptions = Set<AnyCancellable>()
    #endif
        
    init() {
        super.init(font: .regular, textColor: .whiteWithAlpha)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeLabel() {
        super.initializeLabel()
        
        self.isUserInteractionEnabled = true
        self.updateText(for: 0)
    }
    
    func configure(with moment: Moment) {
        #if IOS
        self.subscriptions.forEach { subscription in
            subscription.cancel()
        }
        
        self.controller = ConversationController.controller(for: moment.commentsId)
        
        if let sequence = self.controller?.messageSequence {
            self.updateText(for: sequence.totalUnread)
        } else {
            self.updateText(for: 0)
        }
                
        self.controller?.messageSequenceChangePublisher.mainSink(receiveValue: { [unowned self] _ in
            if let sequence = self.controller?.messageSequence {
                self.updateText(for: sequence.totalUnread)
            } else {
                self.updateText(for: 0)
            }
        }).store(in: &self.subscriptions)
        #endif
    }
    
    private func updateText(for count: Int) {
        var text = ""
        
        if count == 0 {
            text = "Add comment"
        } else if count == 1 {
            text = "View unread comment"
        } else {
            text = "View \(count) unread comments"
        }
        
        self.setText(text)
        self.layoutNow()
    }
}
