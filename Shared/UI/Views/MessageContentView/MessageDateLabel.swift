//
//  MessageDateLabel.swift
//  Jibber
//
//  Created by Benji Dodgson on 4/26/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class RealtimeDateLabel: ThemeLabel, RealtimeHandler {
    
    var timeInterval: TimeInterval?
    
    var timer: Timer?
    
    private var date: Date?
    
    func configure(with date: Date) {
        self.date = date
        self.update(with: date)
        self.initializeTimer()
    }
    
    func timerDidFire() {
        guard let date = self.date else { return }
        self.update(with: date)
    }
    
    private func update(with date: Date) {
        let timeAgo = date.getTimeAgo()
        self.text = timeAgo.string
        self.timeInterval = timeAgo.fromNow.timeInterval
        self.setNeedsLayout()
    }
}

class MessageDateLabel: RealtimeDateLabel {
    
    func configure(with message: Messageable) {
        self.configure(with: message.createdAt)
    }
}
