//
//  MessageDeliveryTypeView.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/26/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class MessageDeliveryTypeSelectionView: BaseView {
    
    let imageView = SymbolImageView()
    let context: MessageDeliveryType
    
    enum State {
        case hidden
        case visible
        case highlighted
    }
    
    private(set) var state: State = .hidden
    
    init(with context: MessageDeliveryType) {
        self.context = context
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.set(backgroundColor: .white)
        self.alpha = 0.5
        
        self.addSubview(self.imageView)
        self.imageView.set(symbol: self.context.symbol)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.squaredSize = 50
        self.makeRound()
        
        self.imageView.squaredSize = self.height * 0.6
        self.imageView.centerOnXAndY()
    }
    
    private var animationTask: Task<Void, Never>?
    
    func update(state: State) {
        guard self.state != state else { return }
        
        self.state = state
        
        // Cancel any currently running tasks so we don't trigger the animation multiple times.
        self.animationTask?.cancel()
        
        self.animationTask = Task { [weak self] in
            guard let self else { return }
            
            switch self.state {
            case .hidden:
                
                await UIView.awaitAnimation(with: .standard, animations: {
                    self.alpha = 0.5
                    self.setNeedsLayout()
                })
                
                await UIView.awaitSpringAnimation(with: .standard, animations: {
                    self.right = 0
                    self.setNeedsLayout()
                })

            case .visible:
                
                await UIView.awaitSpringAnimation(with: .standard, animations: {
                    self.pin(.left, offset: .long)
                    self.setNeedsLayout()
                })
                
                await UIView.awaitAnimation(with: .standard, animations: {
                    self.alpha = 0.5
                })
            case .highlighted:
                
                await UIView.awaitAnimation(with: .standard, animations: {
                    self.alpha = 1.0
                })
            }
        }
    }
}
