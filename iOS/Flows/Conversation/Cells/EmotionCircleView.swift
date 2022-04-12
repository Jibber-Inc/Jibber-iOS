//
//  EmotionCircleView.swift
//  Jibber
//
//  Created by Martin Young on 4/12/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class EmotionCircleView: BaseView {

    private let label = ThemeLabel(font: .small, textColor: .white)

    init(emotion: Emotion) {
        super.init()
        self.configure(with: emotion)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func initializeSubviews() {
        super.initializeSubviews()

        self.clipsToBounds = true
        self.layer.borderWidth = 2
        self.layer.masksToBounds = false

        self.addSubview(self.label)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.layer.cornerRadius = self.halfWidth

        self.label.setSize(withWidth: self.width)
        self.label.centerOnXAndY()
    }

    func configure(with emotion: Emotion) {
        self.label.text = emotion.rawValue

        self.label.textColor = emotion.color
        self.layer.borderColor = emotion.color.cgColor
        self.backgroundColor = emotion.color.withAlphaComponent(0.4)

        self.setNeedsLayout()
    }

    // MARK: - UIDynamicItem
    
    override var collisionBoundsType: UIDynamicItemCollisionBoundsType {
        return .ellipse
    }
}