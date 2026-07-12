//
//  PhoneKit.swift
//  Benji
//
//  Created by Benji Dodgson on 8/10/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import PhoneNumberKit

// PhoneNumberUtility's mutable regex cache is internally protected by an
// NSLock; the remaining instance graph is immutable after initialization.
extension PhoneNumberUtility: @retroactive @unchecked Sendable {}

struct PhoneKit {
    // Phone number kit is really expensive to allocate so create a global shared instance
    static let shared = PhoneNumberUtility()
    static let defaultRegion = PhoneNumberUtility.defaultRegionCode()
}
