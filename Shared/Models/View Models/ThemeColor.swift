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
    
    case B1
    case B2
    case D1
    case D2
    case D3
    case D4
    case D5
    case D6
    case L1
    case L2
    case L3
    case L4
    case L5

    case border
    case background
    case darkGray
    case gray
    case lightGray
    case textColor
    case white
    case clear
    case red

    var color: UIColor {
        switch self {
        case .border:
            return UIColor(named: "BORDER")!
        case .background:
            return UIColor(named: "BACKGROUND")!
        case .darkGray:
            return UIColor(named: "DARKGRAY")!
        case .gray:
            return UIColor(named: "GRAY")!
        case .lightGray:
            return UIColor(named: "LIGHTGRAY")!
        case .textColor:
            return UIColor(named: "TEXTCOLOR")!
        case .white:
            return UIColor(named: "WHITE")!
        case .clear:
            return UIColor(named: "CLEAR")!
        case .red:
            return UIColor(named: "RED")!
            
        case .B1:
            return UIColor(named: "RED")!
        case .B2:
            return UIColor(named: "RED")!
        case .D1:
            return UIColor(named: "RED")!
        case .D2:
            return UIColor(named: "RED")!
        case .D3:
            return UIColor(named: "RED")!
        case .D4:
            return UIColor(named: "RED")!
        case .D5:
            return UIColor(named: "RED")!
        case .D6:
            return UIColor(named: "RED")!
        case .L1:
            return UIColor(named: "RED")!
        case .L2:
            return UIColor(named: "RED")!
        case .L3:
            return UIColor(named: "RED")!
        case .L4:
            return UIColor(named: "RED")!
        case .L5:
            return UIColor(named: "RED")!
        }
    }
    
    var ciColor: CIColor {
        return CIColor(color: self.color)
    }
}
