//
//  PullView.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/19/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class PullView: BaseView {
    
    private let imageView = UIImageView()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.imageView)
        self.imageView.contentMode = .scaleAspectFit
        
        if self.traitCollection.userInterfaceStyle == .dark {
            self.imageView.image = UIImage(named: "pullbar")
        } else {
            self.imageView.image = UIImage(named: "pullbar_light")
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.imageView.height = 12
        self.imageView.width = 20
        self.imageView.centerOnXAndY()
        
        self.height = 24
        self.width = 44
    }
}
