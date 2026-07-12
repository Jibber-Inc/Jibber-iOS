//
//  LocationManager.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/17/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    
    var isAuthorized: Bool {
        return self.authorizationStatus == .authorizedWhenInUse
    }
    
    @Published private(set) var authorizationStatus: CLAuthorizationStatus?
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var currentPlaceMark: CLPlacemark?
    
    override init() {
        super.init()
        self.initialize()
    }
    
    private func initialize() {
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    func requestAuthorization() {
        self.manager.requestWhenInUseAuthorization()
    }
    
    func requestCurrentLocation() {
        self.manager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logDebug(error.localizedDescription)
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus 
    }
}
