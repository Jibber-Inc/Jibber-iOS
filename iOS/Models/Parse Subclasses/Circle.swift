//
//  File.swift
//  File
//
//  Created by Benji Dodgson on 9/17/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

enum CircleKey: String {
    case owner
    case users
    case name
    case theme
    case invitedContacts
    case limit
}

final class Circle: PFObject, PFSubclassing {
    
    enum Theme: String {
        case eggplant
        case squash
        case gum
        case mint
        case saltwater
        case elderberry
    }

    static func parseClassName() -> String {
        return String(describing: self)
    }
    
    var owner: User? {
        get { self.getObject(for: .owner) }
        set { self.setObject(for: .owner, with: newValue) }
    }
    
    var name: String? {
        get { self.getObject(for: .name) }
        set { self.setObject(for: .name, with: newValue)}
    }
    
    var limit: Int {
        get { self.getObject(for: .limit) ?? 9 }
    }
    
    var theme: Theme {
        get {
            guard let themeString: String = self.getObject(for: .theme),
                  let theme = Theme(rawValue: themeString) else { return .eggplant }
                  return theme
        }
        set {
            self.setObject(for: .theme, with: newValue.rawValue)
        }
    }

    var users: [User] {
        get { self.getObject(for: .users) ?? [] }
        set { self.setObject(for: .users, with: newValue) }
    }
    
    var invitedContacts: [String] {
        get { self.getObject(for: .invitedContacts) ?? [] }
        set { self.setObject(for: .invitedContacts, with: newValue) }
    }
    
    func add(people: [Person]) async throws -> Self {
        
        let users: [User] = people.compactMap { person in
            return person.connection?.nonMeUser
        }
        
        if !users.isEmpty {
            self.addUniqueObjects(from: users, forKey: CircleKey.users.rawValue)
        }
        
        let contacts: [String] = people.compactMap { person in
            return person.cnContact?.identifier
        }
        
        if !contacts.isEmpty {
            self.addUniqueObjects(from: contacts, forKey: CircleKey.invitedContacts.rawValue)
        }
        
        return try await self.saveToServer()
    }
}

extension Circle: Objectable {
    typealias KeyType = CircleKey

    func getObject<Type>(for key: CircleKey) -> Type? {
        return self.object(forKey: key.rawValue) as? Type
    }

    func setObject<Type>(for key: CircleKey, with newValue: Type) {
        self.setObject(newValue, forKey: key.rawValue)
    }

    func getRelationalObject<PFRelation>(for key: CircleKey) -> PFRelation? {
        return self.relation(forKey: key.rawValue) as? PFRelation
    }
}
