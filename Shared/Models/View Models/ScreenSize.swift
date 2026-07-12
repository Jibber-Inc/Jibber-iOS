//
//  ScreenSize.swift
//  Benji
//
//  Created by Benji Dodgson on 12/25/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

enum ScreenSize: Int, CaseIterable {
    case phoneSmall = 651 // 4 inches iPhone 5 and SE
    case phoneMedium = 765 // 4.7 inches iPhone 6,7,8
    case phoneLarge = 844 // 5.5 inches iPhone 6+, 7+, 8+
    case phoneExtraLarge = 894 // 5.8 inches iPhoneX
    case tablet = 1280 // iPad Mini & Pro
    case tabletLarge = 1707 // iPad Pro Large

    static func closest(to diagonalDistance: CGFloat) -> ScreenSize {
        let allSizes: [ScreenSize] = ScreenSize.allCases
        var closestDistance: CGFloat = CGFloat.greatestFiniteMagnitude
        var closestScreenSize: ScreenSize = .phoneSmall
        for size in allSizes {
            var screenSizeDiff = diagonalDistance - CGFloat(size.rawValue)
            screenSizeDiff = abs(screenSizeDiff)
            if closestDistance > screenSizeDiff {
                closestDistance = screenSizeDiff
                closestScreenSize = size
            }
        }
        return closestScreenSize
    }
}
