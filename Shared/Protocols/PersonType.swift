//
//  Avatar.swift
//  Benji
//
//  Created by Benji Dodgson on 6/23/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

protocol PersonType: ImageDisplayable {
    /// The unique identifier for this person. It may represent a server generated uuid, or a client-side contact id.
    var personId: String { get }
    var initials: String { get }
    var givenName: String { get }
    var familyName: String { get }
    var fullName: String { get }
    var handle: String { get }
    var focusStatus: FocusStatus? { get }
    var phoneNumber: String? { get }
    var updatedAt: Date? { get }
}

extension PersonType {

    var isCurrentUser: Bool {
        return self.personId == User.current()?.personId
    }
    
    var fullName: String {
        if self.givenName.isEmpty && self.familyName.isEmpty {
            return "Unknown"
        }
        return self.givenName + " " + self.familyName
    }

    var initials: String {
        let firstInitial = String(optional: self.givenName.first?.uppercased())
        let lastInitial = String(optional: self.familyName.first?.uppercased())
        return firstInitial + lastInitial
    }
}
