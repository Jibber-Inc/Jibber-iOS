//
//  PassThroughView.swift
//  Benji
//
//  Created by Benji Dodgson on 7/3/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class PassThroughView: BaseView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}
