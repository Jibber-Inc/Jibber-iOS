//
//  AchievementType.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/16/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

enum AchievementTypeKey: String {
    case bounty
    case title
    case description
    case isRepeatable
    case type
}

final class AchievementType: PFObject, PFSubclassing, @unchecked Sendable {
    
    enum LocalType: String {
        case sendInvite = "INVITE_SENT"
        case firstMessage = "FIRST_MESSAGE"
        case firstUnreadMessage = "FIRST_UNREAD_MESSAGE"
        case groupOfPlus = "GROUP_OF_PLUS"
        case firstGroup = "FIRST_GROUP"
        case firstFeeling = "FIRST_FEELING"
        case firstReply = "FIRST_REPLY"
        case firstExpression = "FIRST_EXPRESSION"
    }

    static func parseClassName() -> String {
        return String(describing: self)
    }

    var bounty: Int {
        get { return self.getObject(for: .bounty) ?? 0 }
    }

    var title: String {
        get { self.getObject(for: .title) ?? "" }
    }

    var descriptionText: String {
        get { self.getObject(for: .description) ?? "" }
    }
    
    var isRepeatable: Bool {
        get { self.getObject(for: .isRepeatable) ?? false }
    }
    
    var type: String? {
        get { self.getObject(for: .type) }
    }
    
    var localType: LocalType? {
        get {
            guard let value = self.type else { return nil }
            return LocalType.init(rawValue: value)
        }
    }
}

extension AchievementType: Objectable {
    typealias KeyType = AchievementTypeKey

    func getObject<Type>(for key: AchievementTypeKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: AchievementTypeKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: AchievementTypeKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}
