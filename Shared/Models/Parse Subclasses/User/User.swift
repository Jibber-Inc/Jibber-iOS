//
//  User.swift
//  Benji
//
//  Created by Benji Dodgson on 11/2/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import JibberParseLiveQuery
import Combine
import SwiftUI

enum ObjectKey: String {
    case objectId
    case createAt
    case updatedAt
}

enum UserKey: String {
    case email
    case phoneNumber
    case givenName
    case familyName
    case smallImage
    case focusImage
    case quePosition
    case status
    case handle
    case connectionPreferences
    case focusStatus
    case timeZone
    case latestContextCue
}

enum UserStatus: String {
    case needsVerification // Has entered a phone number but not a verification code.
    case inactive // Has verified but has not completed required onboarding
    case waitlist // Has verified but has not being granted access to the full app
    case active // Has verified and fully onboardied. Has full access to the app
}

enum FocusStatus: String {
    case focused
    case available
    
    var displayName: String {
        switch self {
        case .focused:
            return "Unavailable"
        case .available:
            return "Available"
        }
    }
    
    var color: ThemeColor {
        switch self {
        case .focused:
            return .yellow
        case .available:
            return .D6
        }
    }
}

final class User: PFUser, @unchecked Sendable {

    var phoneNumber: String? {
        get { return self.getObject(for: .phoneNumber) }
        set { self.setObject(for: .phoneNumber, with: newValue)}
    }

    var givenName: String {
        get { return self.getObject(for: .givenName) ?? String() }
        set { self.setObject(for: .givenName, with: newValue) }
    }

    var familyName: String {
        get { return self.getObject(for: .familyName) ?? String() }
        set { self.setObject(for: .familyName, with: newValue) }
    }

    var handle: String {
        get { return self.getObject(for: .handle) ?? String() }
        set { self.setObject(for: .handle, with: newValue) }
    }

    var smallImage: PFFileObject? {
        get { return self.getObject(for: .smallImage) }
        set { self.setObject(for: .smallImage, with: newValue) }
    }

    var quePosition: Int? {
        get { return self.getObject(for: .quePosition) }
        set { self.setObject(for: .quePosition, with: newValue) }
    }

    var status: UserStatus? {
        get {
            guard let string: String = self.getObject(for: .status) else { return nil }
            return UserStatus(rawValue: string)
        }
        set { self.setObject(for: .status, with: newValue?.rawValue) }
    }

    var focusStatus: FocusStatus? {
        get {
            guard let string: String = self.getObject(for: .focusStatus) else { return nil }
            return FocusStatus(rawValue: string)
        }
        set {
            self.smallImage?.clearCachedDataInBackground()
            self.setObject(for: .focusStatus, with: newValue?.rawValue)
        }
    }
    
    #if IOS
    @MainActor
    var isConnection: Bool {
        return PeopleStore.shared.connectedPeople.contains { type in
            return type.personId == self.personId
        }
    }
    #endif 

    var connectionPreferences: [ConnectionPreference] {
        return self.getObject(for: .connectionPreferences) ?? []
    }
    
    var timeZone: String {
        get { return self.getObject(for: .timeZone) ?? String() }
        set { self.setObject(for: .timeZone, with: newValue) }
    }
    
    #if IOS
    var latestContextCue: ContextCue? {
        get { return self.getObject(for: .latestContextCue) }
        set { self.setObject(for: .latestContextCue, with: newValue) }
    }
    #endif 
}
