//
//  UNNotificationContent+Extensions.swift
//  Benji
//
//  Created by Benji Dodgson on 4/19/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UserNotifications

enum StreamContentKey: String {
    case cid = "cid"
    case messageId = "id"
    case type = "type"
    case author = "author"
}

enum NotificationContentKey: String {
    case author = "author"
    case target = "target"
    case group = "group"
    case deeplink = "deeplink"
    case identifier = "identifier"
    case body = "body"
    case title = "title"
    case subtitle = "subtitle"
    case trigger = "trigger"
    case category = "categoryIdentifier"
    case thread = "threadIdentifier"
    case conversationId = "conversationId"
    case messageId = "messageId"
    case threadRootId = "threadRootId"
    case connectionId = "connectionId"
    case momentId = "momentId"
}

extension UNNotificationContent {

    var author: String? {
        guard let value: String = self.value(for: .author) else { return nil }
        return value
    }

    var messageId: String? {
        guard let value: String = self.value(for: .messageId) else { return nil }
        return value
    }

    var conversationId: String? {
        if let value: String = self.value(for: .conversationId) {
            return value
        } else {
            return nil
        }
    }

    var threadRootId: String? {
        self.value(for: .threadRootId)
    }

    var connectionId: String? {
        guard let value: String = self.value(for: .connectionId) else { return nil }
        return value
    }
    
    var momentId: String? {
        guard let value: String = self.value(for: .momentId) else { return nil }
        return value
    }

    var deepLinkTarget: DeepLinkTarget? {
        if let value: String = self.value(for: .target) {
            return DeepLinkTarget(rawValue: value)
        } else {
            return nil
        }
    }

    var deeplinkURL: URL? {
        guard let value: String = self.value(for: .deeplink) else { return nil }
        return URL(string: value)
    }

    var identifier: String? {
        return self.value(for: .identifier)
    }

    func value<Type>(for key: NotificationContentKey) -> Type? {
        guard let data = self.userInfo["data"] as? [String: Any] else { return nil }
        return data[key.rawValue] as? Type
    }

    func valueFrom<Type>(data: [String: Any], for key: NotificationContentKey) -> Type? {
        return data[key.rawValue] as? Type
    }
}

extension UNMutableNotificationContent {

    func setUserInfo(from data: [String: Any]) {
        self.setValue(for: .target, from: data)
        self.setValue(for: .deeplink, from: data)
        self.setValue(for: .identifier, from: data)

        if let subtitle: String = self.valueFrom(data: data, for: .subtitle) {
            self.subtitle = subtitle
        }

        if let category: String = self.valueFrom(data: data, for: .category) {
            self.categoryIdentifier = category
        }

        if let thread: String = self.valueFrom(data: data, for: .thread) {
            self.threadIdentifier = thread
        }

        self.userInfo = data
    }

    func setValue(for key: NotificationContentKey, from data: [String: Any]) {
        self.userInfo[key.rawValue] = data[key.rawValue]
    }

    func setData(value: Any, for key: NotificationContentKey) {
        var data = self.userInfo["data"] as? [String: Any] ?? [:]
        data[key.rawValue] = value
        self.userInfo["data"] = data
    }
    
    func setStreamData(value: Any, for key: StreamContentKey) {
        var streamData = self.userInfo["stream"] as? [String: Any] ?? [:]
        streamData[key.rawValue] = value
        self.userInfo["stream"] = streamData
    }
}

extension UNNotificationAttachment {
    
    static func getAttachment(url: URL, identifier: String = "image") async -> UNNotificationAttachment? {
        return await withCheckedContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { (downloadedUrl, _, _) in

                guard let downloadedUrl = downloadedUrl else {
                    continuation.resume(returning: nil)
                    return
                }
              
                guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
                    continuation.resume(returning: nil)
                    return
                }
              
                let localURL = URL(fileURLWithPath: path).appendingPathComponent(url.lastPathComponent)
              
                do {
                    try FileManager.default.moveItem(at: downloadedUrl, to: localURL)
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                
                if let attachment = try? UNNotificationAttachment(identifier: identifier, url: localURL, options: nil) {
                    continuation.resume(returning: attachment)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            task.resume()
        }
     }

}
