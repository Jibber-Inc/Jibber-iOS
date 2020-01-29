//
//  DeeplinkTarget.swift
//  Benji
//
//  Created by Benji Dodgson on 6/22/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation

enum DeepLinkTarget : String, CaseIterable, Diffable {
    
    case home
    case login
    case channel
    case routine
    case profile 

    func diffIdentifier() -> NSObjectProtocol {
        return self.rawValue as NSObjectProtocol
    }
}
