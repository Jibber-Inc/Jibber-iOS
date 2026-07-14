//
//  UNNotification+Extension.swift
//  Benji
//
//  Created by Benji Dodgson on 4/19/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UserNotifications

extension UNNotification {
    
    var momentId: String? {
        return self.request.content.momentId
    }

    var messageId: String? {
        return self.request.content.messageId
    }
    
    var conversationId: String? {
        return self.request.content.conversationId
    }

    var threadRootId: String? {
        return self.request.content.threadRootId
    }

    var connectionId: String? {
        return self.request.content.connectionId
    }

    var deepLinkTarget: DeepLinkTarget? {
        return self.request.content.deepLinkTarget
    }

    var deeplinkURL: URL? {
        return self.request.content.deeplinkURL
    }

    var customMetadata: NSMutableDictionary {
        if let data = self.request.content.userInfo["data"] as? [String: Any] {
            return NSMutableDictionary(dictionary: data)
        } else {
            return NSMutableDictionary(dictionary: self.request.content.userInfo)
        }
    }
}
