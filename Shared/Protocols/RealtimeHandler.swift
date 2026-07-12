//
//  RealtimeHandler.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/14/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

@MainActor
protocol RealtimeHandler: AnyObject, Sendable {
    var timeInterval: TimeInterval? { get set }
    var timer: Timer? { get set }
    func initializeTimer()
    func timerDidFire()
}

extension RealtimeHandler {
    
    func initializeTimer() {
        guard let timeInterval = self.timeInterval else { return }
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true, block: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timerDidFire()
            }
        })
    }
}
