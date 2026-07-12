//
//  Notice.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/23/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

enum NoticeKey: String {
    case type
    case attributes
    case priority
    case body
}

final class Notice: PFObject, PFSubclassing {

    enum NoticeType: String {
        case timeSensitiveMessage = "ALERT_MESSAGE"
        case connectionRequest = "CONNECTION_REQUEST"
        case connectionConfirmed = "CONNECTION_CONFIRMED"
        case unreadMessages = "UNREAD_MESSAGES"
        case tip = "TIP"
        case invitePrompt = "INVITE_PROMPT"
        case jibberIntro = "JIBBER_INTRO"
        case messageRead = "MESSAGE_READ" // Deprecated
        case system
        case unknown
    }

    static func parseClassName() -> String {
        return String(describing: self)
    }

    var type: NoticeType {
        get {
            guard let value: String = self.getObject(for: .type), let t = NoticeType(rawValue: value) else {
                let value: String = self.getObject(for: .type) ?? ""
                logError(ClientError.apiError(detail: "Unknown notice type: \(value)"))
                return .unknown
            }
            return t
        }
    }

    var attributes: [String: AnyHashable]? {
        get { self.getObject(for: .attributes) }
    }

    var priority: Int {
        get { self.getObject(for: .priority) ?? 0 }
    }

    var body: String? {
        get { self.getObject(for: .body) }
    }
    
    var unreadConversationIds: [String] {
        guard let value = self.attributes?["unreadMessages"],
              let array = value as? [[String: String]] else { return [] }
        
        return array.compactMap { dict in
            return dict["cid"]
        }
    }
    
    var unreadConversations: [String: [String]] {
        get {
            guard let value = self.attributes?["unreadMessages"],
                  let array = value as? [[String: String]] else { return [:] }
            
            var unread: [String: [String]] = [:]
            
            array.forEach { dict in
                if let cid = dict["cid"],
                   let messageId = dict["messageId"] {
                    
                    if unread.keys.contains(cid) {
                        unread[cid]?.append(messageId)
                    } else {
                        unread[cid] = [messageId]
                    }
                }
            }
            
            return unread
        }
    }
    
    var unreadMessages: [[String: String]] {
        get {
            guard let value = self.attributes?["unreadMessages"],
                  let array = value as? [[String: String]] else { return [[:]] }
            
            var messages: [[String: String]] = []
            
            array.forEach { dict in
                if let cid = dict["cid"],
                   let messageId = dict["messageId"] {
                    messages.append([messageId: cid])
                }
            }
            
            return messages
        }
    }
}

extension Notice: Objectable {
    typealias KeyType = NoticeKey

    func getObject<Type>(for key: NoticeKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: NoticeKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: NoticeKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}
