//
//  ThemeColor.swift
//  Benji
//
//  Created by Benji Dodgson on 12/25/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

enum ThemeColor: String, CaseIterable {
    
    case B0
    case B1
    case B1withAlpha
    case B2
    case B6
    case D1
    case D6
    case BORDER
    case whiteWithAlpha
    
    case badgeTop
    case badgeHighlightTop
    case badgeHighlightBottom
    
    case white
    case clear
    case red
    case yellow

    var color: UIColor {
        switch self {
            
        case .white:
            return UIColor(named: "WHITE")!
        case .clear:
            return UIColor(named: "CLEAR")!
        case .red:
            return UIColor(named: "RED")!
        case .yellow:
            return UIColor(named: "YELLOW")!
        case .B1:
            return UIColor(named: "B1")!
        case .B0:
            return UIColor(named: "B0")!
        case .B1withAlpha:
            return ThemeColor.B1.color.withAlphaComponent(0.3)
        case .B2:
            return UIColor(named: "B2")!
        case .B6:
            return UIColor(named: "B6")!
        case .D1:
            return UIColor(named: "D1")!
        case .D6:
            return UIColor(named: "D6")!
        case .BORDER:
            return UIColor(named: "BORDER")!
        case .whiteWithAlpha:
            return ThemeColor.white.color.withAlphaComponent(0.35)
        
            
        case .badgeTop:
            return UIColor(named: "BADGE_TOP")!
            
        case .badgeHighlightTop:
            return UIColor(named: "BADGE_HIGHLIGHT_TOP")!
        case .badgeHighlightBottom:
            return UIColor(named: "BADGE_HIGHLIGHT_BOTTOM")!
        }
    }
    
    var ciColor: CIColor {
        return CIColor(color: self.color)
    }
}
