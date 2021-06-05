//
//  UserPrefrences.swift
//  Ours
//
//  Created by Benji Dodgson on 6/5/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Parse
import Combine

enum UserPrefrencesKey: String {
    case swipeAnimationViewCount
    case keyboardInstructionsCount

}

final class UserPrefrences: PFObject, PFSubclassing {

    static func parseClassName() -> String {
        return String(describing: self)
    }

    var swipeAnimationCount: Int? {
        get { return self.getObject(for: .swipeAnimationViewCount) }
        set { self.setObject(for: .swipeAnimationViewCount, with: newValue) }
    }

    var keyboardInstructionsCount: Int? {
        get { return self.getObject(for: .keyboardInstructionsCount) }
        set { self.setObject(for: .keyboardInstructionsCount, with: newValue) }
    }

    static func getLocal() -> Future<UserPrefrences, Error> {
        return Future { promise in
            if let query = Self.query() {
                query.fromLocalDatastore()
                query.getFirstObjectInBackground { object, error in
                    if let up = object as? Self {
                        promise(.success(up))
                    } else {
                        promise(.failure(ClientError.message(detail: "Failed to retrieve local data.")))
                    }
                }
            }
        }
    }

    func pin() -> Future<Void, Error> {
        return Future { promise in
            self.pinInBackground { success, error in
                if success {
                    promise(.success(()))
                } else {
                    promise(.failure(ClientError.message(detail: "Failed to save data locally")))
                }
            }
        }
    }
}

extension UserPrefrences: Objectable {
    typealias KeyType = UserPrefrencesKey

    func getObject<Type>(for key: UserPrefrencesKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: UserPrefrencesKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: UserPrefrencesKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}

