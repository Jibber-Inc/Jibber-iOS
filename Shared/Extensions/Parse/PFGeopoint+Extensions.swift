//
//  PFGeopoint+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/20/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

extension PFGeoPoint {
    
    var clLocation: CLLocation? {
        return CLLocation(latitude: self.latitude, longitude: self.longitude)
    }
}
