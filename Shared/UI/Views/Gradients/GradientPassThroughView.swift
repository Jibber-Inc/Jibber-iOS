//
//  GradientPassThroughView.swift
//  Benji
//
//  Created by Benji Dodgson on 7/3/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import QuartzCore
import UIKit

class GradientLayer: CAGradientLayer {

    init(with colors: [ThemeColor],
         startPoint: CAGradientLayer.Point,
         endPoint: CAGradientLayer.Point) {
        
        let cgColors = colors.compactMap { color in
            return color.color.cgColor
        }
        
        super.init()
        self.startPoint = startPoint.point
        self.endPoint = endPoint.point
        self.colors = cgColors
        self.type = .axial
    }
    
    func updateColors(with colors: [ThemeColor]) {
        let cgColors = colors.compactMap { color in
            return color.color.cgColor
        }
        
        self.updateCGColors(with: cgColors)
    }
    
    func updateCGColors(with colors: [CGColor]) {
        self.colors = colors
        self.setNeedsLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(layer: Any) {
        super.init()
    }
}

class GradientPassThroughView: PassThroughView {

    private lazy var gradient = CAGradientLayer(start: self.start,
                                                end: self.end,
                                                colors: self.colors,
                                                type: .axial)
    private let colors: [CGColor]
    private let start: CAGradientLayer.Point
    private let end: CAGradientLayer.Point

    init(with colors: [CGColor],
         startPoint: CAGradientLayer.Point,
         endPoint: CAGradientLayer.Point) {

        self.colors = colors
        self.start = startPoint
        self.end = endPoint
        
        super.init()

        self.layer.insertSublayer(self.gradient, at: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        self.gradient.frame = self.bounds
        CATransaction.commit()
    }
}
