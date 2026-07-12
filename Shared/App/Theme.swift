//
//  BenjiTheme.swift
//  Benji
//
//  Created by Benji Dodgson on 12/25/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

struct Theme {

    enum AnimationDuration {
        case fast
        case standard
        case slow
        case custom(CGFloat)

        var value: TimeInterval {
            switch self {
            case .fast:
                return 0.2
            case .standard:
                return 0.35
            case .slow:
                return 0.5
            case .custom(let time):
                return time
            }
        }
    }

    indirect enum ContentOffset {

        case noOffset
        case short
        case standard
        case long
        case xtraLong
        case screenPadding
        case custom(CGFloat)
        case negative(ContentOffset)

        var value: CGFloat {
            switch self {
            case .noOffset:
                return 0
            case .short:
                return 4
            case .standard:
                return 8
            case .long:
                return 12
            case .xtraLong:
                return 16
            case .screenPadding:
                return 32
            case .custom(let value):
                return value
            case .negative(let offset):
                return offset.value * -1
            }
        }
    }

    static let animationDurationFast: TimeInterval = 0.2
    static let animationDurationStandard: TimeInterval = 0.35
    static let animationDurationSlow: TimeInterval = 0.5
    static let cornerRadius: CGFloat = 10
    static let screenRadius: CGFloat = 30 
    static let innerCornerRadius: CGFloat = Theme.cornerRadius.half
    static let borderWidth: CGFloat = 2
    static let buttonHeight: CGFloat = 50
    static let iPadPortraitWidthRatio: CGFloat = 0.65
    @MainActor static let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
    @MainActor static let darkBlurEffect = UIBlurEffect.init(style: .dark)

    static func getPaddedWidth(with width: CGFloat) -> CGFloat {
        return width - ContentOffset.xtraLong.value.doubled
    }

    private init() {}
}
