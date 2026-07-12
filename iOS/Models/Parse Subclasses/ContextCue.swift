//
//  ContextCue.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/6/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

enum ContextCueKey: String {
    case owner
    case emojis
    case message
    case attributes
}

final class ContextCue: PFObject, PFSubclassing {

    static func parseClassName() -> String {
        return String(describing: self)
    }
    
    var owner: User? {
        get { self.getObject(for: .owner) }
        set { self.setObject(for: .owner, with: newValue) }
    }
    
    var emojis: [String] {
        get { self.getObject(for: .emojis) ?? [] }
        set { self.setObject(for: .emojis, with: newValue)}
    }
    
    var emojiString: String {
        var value: String = ""
        self.emojis.forEach { emoji in
            value.append(emoji)
        }
        return value
    }
    
    var message: String? {
        get { self.getObject(for: .message) }
        set { self.setObject(for: .message, with: newValue) }
    }
    
    var attributes: [String: AnyHashable]? {
        get { self.getObject(for: .attributes) }
        set { self.setObject(for: .attributes, with: newValue) }
    }
    
    static func fetchAll(for user: User) async throws -> [ContextCue] {
        let objects: [ContextCue] = try await withCheckedThrowingContinuation { continuation in
            guard let query = self.query() else {
                continuation.resume(throwing: ClientError.apiError(detail: "Query was nil"))
                return
            }
            query.whereKey("owner", equalTo: user)
            query.findObjectsInBackground { objects, error in
                if let objs = objects as? [ContextCue] {
                    continuation.resume(returning: objs)
                } else if let e = error {
                    continuation.resume(throwing: e)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }

        return objects
    }
}

extension ContextCue: Objectable {
    typealias KeyType = ContextCueKey

    func getObject<Type>(for key: ContextCueKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: ContextCueKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: ContextCueKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}
