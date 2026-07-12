//
//  ConnectionPreference.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/3/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

enum ConnectionPreferenceKey: String {
    case nickname = "nickname"
    case bio = "bio"
}

final class ConnectionPreference: PFObject, PFSubclassing, @unchecked Sendable {

    static func parseClassName() -> String {
        return String(describing: self)
    }

    var nickname: String? {
        get {
            return self.getObject(for: .nickname)
        }
        set {
            self.setObject(for: .nickname, with: newValue)
        }
    }

    var bio: String? {
        get {
            return self.getObject(for: .bio)
        }
        set {
            self.setObject(for: .bio, with: newValue)
        }
    }
}

extension ConnectionPreference: Objectable {
    typealias KeyType = ConnectionPreferenceKey

    func getObject<Type>(for key: ConnectionPreferenceKey) -> Type? {
        self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: ConnectionPreferenceKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: ConnectionPreferenceKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}
