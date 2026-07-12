//
//  QuePositions.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/5/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import ParseLiveQuery

enum QuePositionsKey: String {
    case max = "maxQuePostions"
    case unclaimed = "unclaimedPostion"
    case claimed = "claimedPosition"
}

final class QuePositions: PFObject, PFSubclassing {

    static func parseClassName() -> String {
        return String(describing: self)
    }

    var max: Int {
        return self.getObject(for: .max) ?? 0
    }

    var unclaimed: Int {
        return self.getObject(for: .unclaimed) ?? 0
    }

    var claimed: Int {
        return self.getObject(for: .claimed) ?? 0 
    }
}

extension QuePositions: Objectable {
    typealias KeyType = QuePositionsKey

    func getObject<Type>(for key: QuePositionsKey) -> Type? {
        self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: QuePositionsKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: QuePositionsKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}
