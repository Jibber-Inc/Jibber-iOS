//
//  LocationToggleView.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/24/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

class LocationToggleView: ToggleView {
    
    init() {
        super.init(type: .location)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        LocationManager.shared.$authorizationStatus.mainSink { [unowned self] status in
            self.isON = LocationManager.shared.isAuthorized
        }.store(in: &self.cancellables)
        
        LocationManager.shared.$currentLocation.mainSink { [unowned self] location in
            if let current = location {
                Task {
                    await self.label.setText(current.getStreetString())
                    self.layoutNow()
                }
            } else {
                self.label.setText("Location")
                self.layoutNow()
            }
            
        }.store(in: &self.cancellables)
    }
    
    override func update(isON: Bool) {
        super.update(isON: isON)
        
        guard self.alpha != 0 else { return }

        Task {
            if self.isON {
                if !LocationManager.shared.isAuthorized {
                    LocationManager.shared.requestAuthorization()
                } else {
                    await ToastScheduler.shared.schedule(toastType: .success(.mappingPin, "Location added"), duration: 3)
                }
            } else {
                await ToastScheduler.shared.schedule(toastType: .success(.mappingPin, "Location removed"), duration: 3)
            }
        }
    }
}
