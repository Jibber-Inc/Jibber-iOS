//
//  ShortcutButton.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/14/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class ShortcutButton: BaseView, HomeStateHandler {
    
    static let height: CGFloat = 60
    
    let button = ThemeButton()
    let darkBlur = DarkBlurView()

    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.alpha = 0
        self.transform = CGAffineTransform.init(scaleX: 1.5, y: 1.5)
        
        self.button.set(style: .image(symbol: .boltFill,
                                      palletteColors: [.D6],
                                      pointSize: 26,
                                      backgroundColor: .clear))

        self.layer.borderColor = ThemeColor.D6.color.cgColor
        self.layer.borderWidth = 2
        self.button.layer.shadowColor = ThemeColor.red.color.cgColor
        self.button.layer.shadowOpacity = 0.15
        self.button.layer.shadowOffset = .zero
        self.button.layer.shadowRadius = 12
        
        self.insertSubview(self.darkBlur, at: 0)
        self.insertSubview(self.button, at: 1)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
                
        self.darkBlur.expandToSuperviewSize()
        self.button.expandToSuperviewSize()
        
        self.makeRound()
    }
    
    private var stateTask: Task<Void, Never>?

    func handleHome(state: HomeState) {
        self.stateTask?.cancel()
        
        self.stateTask = Task { [weak self] in
            guard let self else { return }
            
            await UIView.awaitSpringAnimation(with: .custom(1.0), animations: {
                switch state {
                case .initial:
                    self.transform = CGAffineTransform.init(scaleX: 1.5, y: 1.5)
                    self.alpha = 0
                case .tabs, .shortcuts, .dismissShortcuts:
                    self.transform = .identity
                    self.alpha = 1.0
                    
                    self.button.isSelected = state == .shortcuts
                }
                
                self.setNeedsLayout()
            })
        }
    }
}
