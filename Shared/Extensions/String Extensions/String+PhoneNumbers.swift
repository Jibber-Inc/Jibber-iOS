//
//  String+PhoneNumbers.swift
//  Jibber
//
//  Created by Benji Dodgson on 10/26/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import PhoneNumberKit

extension String {

    func isValidPhoneNumber(for region: String) -> Bool {
        return !self.parsePhoneNumber(for: region).isNil
    }

    func parsePhoneNumber(for region: String) -> PhoneNumber? {
        return try? PhoneKit.shared.parse(self, withRegion: region)
    }

    func formatPhoneNumber() -> String? {
        return try? PhoneKit.shared.parse(self, withRegion: PhoneKit.defaultRegion).numberString
    }

    func removeAllNonNumbers() -> String {
        return self.filter("0123456789".contains)
    }
}

/// A phone number that is considered equal if the last ten digits are the same as another fuzzy phone number.
/// NOTE: This equality check can fail and may (rarely) result in false positives.
struct FuzzyPhoneNumber: Hashable {

    let partialNumber: Substring

    init(_ phoneNumber: String) {
        self.partialNumber = phoneNumber.removeAllNonNumbers().suffix(10)
    }
}
