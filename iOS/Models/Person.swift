//
//  Contact.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/28/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Contacts
import PhoneNumberKit
import ParseCore

struct Person: PersonType, Hashable, Comparable {

    static func < (lhs: Person, rhs: Person) -> Bool {
        if lhs.connection.exists && rhs.connection.exists {
            return lhs.familyName < rhs.familyName
        } else if lhs.cnContact.exists && rhs.cnContact.exists {
            return lhs.familyName < rhs.familyName
        } else {
            return false 
        }
    }

    var personId: String
    var phoneNumber: String?
    
    var familyName: String
    var givenName: String
    
    var updatedAt: Date? {
        return self.user?.updatedAt
    }
    
    var handle: String {
        return self.user?.handle ?? ""
    }
    var focusStatus: FocusStatus? {
        return nil
    }

    var image: UIImage?
    
    var highlightText: String?

    var cnContact: CNContact?
    var user: User?
    var connection: Connection?

    var isSelected: Bool
    
    @MainActor
    init(withContact contact: CNContact, isSelected: Bool = false) {
        self.personId = contact.personId
        self.phoneNumber = contact.phoneNumber

        self.image = contact.image
        self.cnContact = contact
        self.givenName = contact.givenName
        self.familyName = contact.familyName
        self.isSelected = isSelected
    }
    
    init(user: User, connection: Connection?, isSelected: Bool = false) {
        self.personId = user.personId
        self.user = user
        self.phoneNumber = user.phoneNumber
        self.connection = connection
        self.isSelected = isSelected

        self.givenName = user.givenName
        self.familyName = user.familyName
    }
    
    mutating func updateHighlight(text: String?) {
        self.highlightText = text
    }
    
    func contains(_ filter: String?) -> Bool {
        guard let filterText = filter else { return true }
        if filterText.isEmpty { return true }
        let lowercasedFilter = filterText.lowercased()
        return self.fullName.lowercased().contains(lowercasedFilter)
    }
}
