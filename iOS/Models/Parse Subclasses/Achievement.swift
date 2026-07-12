//
//  Achievement.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/18/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

enum AchievementKey: String {
    case type
    case attributes
    case amount
    case transaction
}

final class Achievement: PFObject, PFSubclassing {

    static func parseClassName() -> String {
        return String(describing: self)
    }

    var type: AchievementType? {
        get { self.getObject(for: .type) }
        set { self.setObject(for: .type, with: newValue) }
    }
    
    var transaction: Transaction? {
        get { self.getObject(for: .transaction) }
        set { self.setObject(for: .transaction, with: newValue) }
    }

    var attributes: [String: AnyHashable]? {
        get { self.getObject(for: .attributes) }
    }

    var amount: Double? {
        get { self.getObject(for: .amount) }
        set { self.setObject(for: .amount, with: newValue) }
    }
}

extension Achievement: Objectable {
    typealias KeyType = AchievementKey

    func getObject<Type>(for key: AchievementKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: AchievementKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: AchievementKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}

