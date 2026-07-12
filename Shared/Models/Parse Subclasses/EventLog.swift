//
//  EventLog.swift
//  Jibber
//
//  Created by Martin Young on 1/5/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

enum EventLogKey: String {
    case provider = "provider"
    case eventType = "eventType"
    case payload = "payload"
}

final class EventLog: PFObject, PFSubclassing {

    static func parseClassName() -> String {
        return String(describing: self)
    }

    /// Private var used to guarantee that an event type is provided.
    private let eventTypeString: String

    init(eventType: String) {
        self.eventTypeString = eventType

        super.init()

        self.provider = "iOS"
        self.eventType = self.eventTypeString
    }

    var provider: String? {
        get { return self.getObject(for: .provider) }
        set { self.setObject(for: .provider, with: newValue) }
    }

    var eventType: String? {
        get { return self.getObject(for: .eventType) }
        set { self.setObject(for: .eventType, with: newValue) }
    }

    var payload: [String : Any]? {
        get { return self.getObject(for: .payload) }
        set { self.setObject(for: .payload, with: newValue) }
    }
}

extension EventLog: Objectable {

    typealias KeyType = EventLogKey

    func getObject<Type>(for key: EventLogKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: EventLogKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: EventLogKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}
