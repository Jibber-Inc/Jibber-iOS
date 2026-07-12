//
//  LocationDetailView.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/20/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class LocationDetailView: BaseView {
    
    let label = ThemeLabel(font: .smallBold)
    let imageView = SymbolImageView(symbol: .mappingPin)
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.label)
        self.addSubview(self.imageView)
        self.imageView.set(symbol: .mappingPin)
        self.isVisible = false 
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.imageView.squaredSize = self.height
        self.imageView.pin(.left)
        self.imageView.pin(.top)
        
        self.label.setSize(withWidth: self.width - self.imageView.width - Theme.ContentOffset.standard.value)
        self.label.match(.left, to: .right, of: self.imageView, offset: .standard)
        self.label.centerY = self.imageView.centerY
    }
    
    func configure(with moment: Moment) async {
        if let locationString = await moment.location?.clLocation?.getLocationString(), !locationString.isEmpty {
            self.label.setText(locationString)
            self.isVisible = true
        } else {
            self.isVisible = false
        }
        
        self.layoutNow()
    }
}
