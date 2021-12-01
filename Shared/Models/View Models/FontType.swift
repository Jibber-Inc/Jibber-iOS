//
//  Font.swift
//  Benji
//
//  Created by Benji Dodgson on 12/27/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

private let boldFontName = "SFProText-Bold"
private let regularFontName = "SFProText-Regular"

enum FontType {

    case display
    case medium
    case mediumBold
    case regular
    case regularBold
    case small
    case smallBold
    case reactionEmoji

    var font: UIFont {
        switch self {
        case .display, .medium, .regular, .small:
            return UIFont(name: regularFontName, size: self.size)!
        case .mediumBold, .regularBold, .smallBold:
            return UIFont(name: boldFontName, size: self.size)!
        case .reactionEmoji:
            return UIFont.systemFont(ofSize: self.size)
        }
    }

    var size: CGFloat {
        switch self {
        case .display:
            return 40
        case .medium, .mediumBold:
            return 24
        case .regular, .regularBold:
            return 16
        case .small, .smallBold:
            return 12
        case .reactionEmoji:
            return 10
        }
    }

    var kern: CGFloat {
        switch self {
        default:
            return 1
        }
    }

    var underlineStyle: NSUnderlineStyle {
        return []
    }
}
