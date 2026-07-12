//
//  LocalTimeLabel.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/14/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class LocalTimeLabel: ThemeLabel, RealtimeHandler {
    
    var timeInterval: TimeInterval?
    var timer: Timer?
    
    private var user: User?
    
    func configure(with user: User) {
        self.user = user
        self.timeInterval = 10
        self.update(with: user)
        self.initializeTimer()
    }
    
    func timerDidFire() {
        guard let user = self.user else { return }
        self.update(with: user)
    }
    
    private func update(with user: User) {
        self.text = self.getLocalTime(for: user)
        self.layoutNow()
    }
    
    func getLocalTime(for user: User) -> String {
        let timeZone: TimeZone?
        if user.isCurrentUser {
            timeZone = TimeZone.current
        } else {
            let timeZoneId = user.timeZone
            timeZone = TimeZone.init(identifier: timeZoneId)
        }
        
        let formatter = Date.hourMinuteTimeOfDay
        formatter.timeZone = timeZone
        let localTime = formatter.string(from: Date())
        return localTime.isEmpty ? "Unknown" : localTime
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.setSize(withWidth: 200)
    }
}
