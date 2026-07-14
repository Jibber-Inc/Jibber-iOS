//
//  RepliesBadgeView.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/30/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import ScrollCounter

class RepliesBadgeView: BadgeCounterView {
    
    var replyCounter = NumberScrollCounter(value: 0,
                                           scrollDuration: Theme.animationDurationSlow,
                                           decimalPlaces: 0,
                                           prefix: "",
                                           suffix: nil,
                                           seperator: "",
                                           seperatorSpacing: 0,
                                           font: FontType.xtraSmall.font,
                                           textColor: ThemeColor.B0.color,
                                           animateInitialValue: true,
                                           gradientColor: nil,
                                           gradientStop: nil)
    
    enum State {
        case initial
        case unreadReplies
        case incomplete
        case totalReplies
    }
    
    @Published var state: State = .initial
    
    override func initializeSubviews() {
        super.initializeSubviews()
                
        self.$state.mainSink { [unowned self] state in
            self.handle(state: state)
        }.store(in: &self.cancellables)
    }
    
    func configure(with message: Messageable) {
        if message.totalUnreadReplyCount > 0 {
            self.state = .unreadReplies
        } else if message.recentReplies.count < message.totalReplyCount {
            // A three-item preview cannot prove that older replies are read.
            // Preserve a distinct violet state until the thread is fully
            // hydrated instead of presenting neutral styling as authoritative.
            self.state = .incomplete
        } else {
            self.state = .totalReplies
        }
        
        self.set(value: message.totalReplyCount)
    }
    
    private func handle(state: State) {
        
        UIView.animate(withDuration: Theme.animationDurationFast) {
            switch state {
            case .initial:
                self.alpha = 0
            case .unreadReplies:
                self.alpha = 1.0
                self.set(backgroundColor: .D6)
            case .incomplete:
                self.alpha = 1.0
                self.backgroundColor = ThemeColor.D6.color.withAlphaComponent(0.5)
            case .totalReplies:
                self.set(backgroundColor: .B2)
            }
        } completion: { _ in
            
        }
    }
}
