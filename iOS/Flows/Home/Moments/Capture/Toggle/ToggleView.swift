//
//  ToggleView.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/21/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Combine
import Foundation
import UIKit

class ToggleView: BaseView {
    
    enum ToggleType {
        case location
        case weather
        case emotions
        
        var symbol: ImageSymbol {
            switch self {
            case .location:
                return .mappingPin
            case .weather:
                return .cloudRain
            case .emotions:
                return .heart
            }
        }
        
        var text: String {
            switch self {
            case .location:
                return "Location"
            case .weather:
                return "Weather"
            case .emotions:
                return "Emotions"
            }
        }
    }
    
    let label = ThemeLabel(font: .small)
    let button = ThemeButton()
    @Published var isON: Bool = false
   
    private let type: ToggleType
    
    init(type: ToggleType) {
        self.type = type
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.alpha = 0
        
        self.clipsToBounds = false
        self.addSubview(self.label)
        self.label.textAlignment = .center
        self.label.setTextColor(.white)
        self.addSubview(self.button)
        
        self.button.didSelect { [unowned self] in
            self.isON.toggle()
        }
        
        self.$isON.mainSink { [unowned self] isON in
            self.update(isON: isON)
        }.store(in: &self.cancellables)
        
        self.label.setText(type.text)
        self.button.set(style: .image(symbol: type.symbol, palletteColors: [.white], pointSize: 24, backgroundColor: .whiteWithAlpha))
    }
    
    func update(isON: Bool) {

        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.button.alpha = isON ? 1.0 : 0.25
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.width = 70
        self.height = 100
        
        self.button.squaredSize = self.width
        self.button.pin(.top)
        self.button.centerOnX()
        self.button.makeRound()
        
        self.label.setSize(withWidth: self.width.doubled)
        self.label.match(.top, to: .bottom, of: self.button, offset: .standard)
        self.label.centerOnX()
    }
}
