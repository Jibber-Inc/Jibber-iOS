//
//  ParseEventLogger.swift
//  Jibber
//
//  Created by Martin Young on 1/4/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

class EventLogger {

    static func trackEvent(_ name: String) {
        let eventLog = EventLog(eventType: name)
        eventLog.saveEventually()
    }
}
