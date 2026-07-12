//
//  UIScreen+Extensions.swift
//  Benji
//
//  Created by Benji Dodgson on 12/25/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

extension UIScreen {
    var currentSize: ScreenSize {
        return ScreenSize.closest(to: self.diagonalDistance)
    }

    var diagonalDistance: CGFloat {
        let width: CGFloat = self.bounds.width
        let height: CGFloat = self.bounds.height
        return sqrt(width * width + height * height)
    }

    func isEqualTo(screenSize: ScreenSize) -> Bool {
        return Int(self.diagonalDistance) == screenSize.rawValue
    }

    func isSmallerThan(screenSize: ScreenSize) -> Bool {
        return Int(self.diagonalDistance) < screenSize.rawValue
    }

    func isLargerThan(screenSize: ScreenSize) -> Bool {
        return Int(self.diagonalDistance) > screenSize.rawValue
    }

    func isLargerThanOrEqualTo(screenSize: ScreenSize) -> Bool {
        return Int(self.diagonalDistance) >= screenSize.rawValue
    }
}
