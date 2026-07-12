//
//  AnimationDuration.swift
//  Benji
//
//  Created by Benji Dodgson on 2/9/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

/// Helper for easily setting/animating the transform coordinates of a UIView
enum AnimationPosition {

    case left
    case right
    case up
    case down
    case inward
    case outward

    @MainActor
    func xPosition(view: UIView, multiplier: CGFloat = 0.5) -> CGFloat {
        switch self {
        case .left:
            return -view.width * multiplier
        case .right:
            return view.width * multiplier
        default:
            return .zero
        }
    }

    @MainActor
    func yPosition(view: UIView, multiplier: CGFloat) -> CGFloat {
        switch self {
        case .up:
            return -view.height * multiplier
        case .down:
            return view.height * multiplier
        default:
            return .zero
        }
    }

    @MainActor
    func getTransform(for view: UIView, multiplier: CGFloat = 0.5) -> CGAffineTransform {
        switch self {
        case .left, .right:
            return CGAffineTransform(translationX: self.xPosition(view: view, multiplier: multiplier), y: 0.0)
        case .up, .down:
            return CGAffineTransform(translationX: 0.0, y: self.yPosition(view: view, multiplier: multiplier))
        case .inward:
            return CGAffineTransform(scaleX: 0.9, y: 0.9)
        case .outward:
            return CGAffineTransform(scaleX: 1.1, y: 1.1)
        }
    }
}
