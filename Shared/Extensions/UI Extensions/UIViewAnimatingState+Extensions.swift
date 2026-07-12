//
//  UIViewAnimatingState+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/15/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

extension UIViewAnimatingState: @retroactive CustomStringConvertible, @retroactive CustomDebugStringConvertible {
    
    var isValid: Bool {
        switch self {
        case .inactive, .active, .stopped:
            return true
        default:
            return false
        }
    }

    public var description: String {
        switch self {
        case .inactive:
            return "inactive"
        case .active:
            return "active"
        case .stopped:
            return "stopped"
        default:
            return "\(rawValue)"
        }
    }

    public var debugDescription: String {
        return self.description
    }
}
