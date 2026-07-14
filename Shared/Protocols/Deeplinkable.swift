//
//  Deeplinkable.swift
//  Benji
//
//  Created by Benji Dodgson on 6/22/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator

protocol DeepLinkHandler {
    func handle(deepLink: DeepLinkable)
}

protocol DeepLinkable {
    var customMetadata: NSMutableDictionary { get set }
    var deepLinkTarget: DeepLinkTarget? { get set }
    var reservationId: String? { get set }
    var reservationCreatorId: String? { get set }
    var passId: String? { get set }
}

extension DeepLinkable {
    subscript(key: String) -> Any? {
        get {
            return self.customMetadata[key]
        }

        set (newValue) {
            self.customMetadata[key] = newValue
        }
    }
}

extension DeepLinkable {

    var conversationId: String? {
        get {
            return self.customMetadata.value(forKey: "conversationId") as? String
        }
        set {
            self.customMetadata.setValue(newValue, forKey: "conversationId")
        }
    }
    
    var momentId: String? {
        get {
            return self.customMetadata.value(forKey: "momentId") as? String
        }
        set {
            self.customMetadata.setValue(newValue, forKey: "momentId")
        }
    }
    
    var personId: String? {
        get {
            return self.customMetadata.value(forKey: "personId") as? String
        }
        set {
            self.customMetadata.setValue(newValue, forKey: "personId")
        }
    }

    var messageId: String? {
        get {
            return self.customMetadata.value(forKey: "messageId") as? String
        }
        set {
            self.customMetadata.setValue(newValue, forKey: "messageId")
        }
    }

    var threadRootId: String? {
        get {
            return self.customMetadata.value(forKey: "threadRootId") as? String
        }
        set {
            self.customMetadata.setValue(newValue, forKey: "threadRootId")
        }
    }

    var reservationId: String? {
        get {
            return self.customMetadata.value(forKey: "reservationId") as? String
        }
        set {
            self.customMetadata.setValue(newValue, forKey: "reservationId")
        }
    }

    var reservationCreatorId: String? {
        get {
            return self.customMetadata.value(forKey: ReservationKey.createdBy.rawValue) as? String
        }
        set {
            self.customMetadata.setValue(newValue, forKey: ReservationKey.createdBy.rawValue)
        }
    }

    var passId: String? {
        get {
            return self.customMetadata.value(forKey: "passId") as? String
        }
        set {
            self.customMetadata.setValue(newValue, forKey: "passId")
        }
    }
}
