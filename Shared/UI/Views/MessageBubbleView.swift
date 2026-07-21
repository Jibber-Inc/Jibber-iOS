//
//  MessageSpeechBubble.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/6/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class MessageBubbleView: SpeechBubbleView {
    
    let backgroundLayer = CAShapeLayer()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.backgroundLayer.fillColor = ThemeColor.B0.color.cgColor
        self.layer.insertSublayer(self.backgroundLayer, below: self.bubbleLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        CATransaction.begin()
        self.backgroundLayer.frame = self.bubbleLayer.bounds
        CATransaction.commit()
    }
    
    override func updateBubblePath() -> CGPath {
        let path = super.updateBubblePath()
                
        self.backgroundLayer.path = path
        
        return path
    }
}
