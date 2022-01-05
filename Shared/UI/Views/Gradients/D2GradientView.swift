//
//  D2GradientView.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/5/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class D2GradientView: BaseView {
    
    private let gradientView = D4GradientView()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        //self.set(backgroundColor: .D2)
        self.addSubview(self.gradientView)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.gradientView.expandToSuperviewSize()
    }
}
