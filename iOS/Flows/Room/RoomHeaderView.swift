//
//  RoomHeaderView.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/31/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class RoomHeaderView: BaseView {
    
    let jibImageView = UIImageView(image: UIImage(named: "jiblogo"))
    
    let button = ThemeButton()
    let nameLabel = ThemeLabel(font: .regularBold)
    let focusCircle = BaseView()
    
    let roomNavButton = RoomNavigationButton()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.jibImageView)
        self.jibImageView.contentMode = .scaleToFill
        self.jibImageView.isUserInteractionEnabled = true 
        
        self.addSubview(self.nameLabel)
        if let name = User.current()?.givenName {
            self.nameLabel.setText(name)
        }
        
        self.addSubview(self.focusCircle)
        if let status = User.current()?.focusStatus {
            self.focusCircle.set(backgroundColor: status.color)
        } else {
            self.focusCircle.set(backgroundColor: FocusStatus.focused.color)
        }
        
        self.addSubview(self.button)
        
        self.addSubview(self.roomNavButton)
        self.roomNavButton.configure(for: .outer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.jibImageView.squaredSize = 44
        self.jibImageView.pin(.right, offset: .long)
        self.jibImageView.centerOnY()
        
        self.nameLabel.setSize(withWidth: self.width)
        self.nameLabel.centerOnY()
        self.nameLabel.centerX = self.centerX + Theme.ContentOffset.standard.value
        
        self.focusCircle.squaredSize = 10
        self.focusCircle.makeRound()
        self.focusCircle.match(.right, to: .left, of: self.nameLabel, offset: .negative(.standard))
        self.focusCircle.centerY = self.nameLabel.centerY
        
        self.button.expandToSuperviewHeight()
        self.button.width = self.focusCircle.width + Theme.ContentOffset.standard.value + self.nameLabel.width
        self.button.centerOnXAndY()
        
        self.roomNavButton.pin(.left, offset: .long)
        self.roomNavButton.centerY = self.jibImageView.centerY
    }
}