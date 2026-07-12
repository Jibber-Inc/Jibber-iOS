//
//  CLLocation+Extensions.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/25/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit

extension CLLocation {
    
    func getMapItem() async -> MKMapItem? {
        guard let request = MKReverseGeocodingRequest(location: self) else { return nil }
        return try? await request.mapItems.first
    }
    
    func getLocationString() async -> String {
        guard let representations = await self.getMapItem()?.addressRepresentations else { return "" }
        return representations.fullAddress(includingRegion: false, singleLine: false) ?? ""
    }
    
    func getStreetString() async -> String {
        guard let representations = await self.getMapItem()?.addressRepresentations,
              let address = representations.fullAddress(includingRegion: false, singleLine: false)
        else { return "" }
        return address.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
    }
}
