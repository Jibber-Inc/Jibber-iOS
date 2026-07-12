//
//  MomentReactionsView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/20/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

class MomentReactionsView: BaseView {
    
    let button = ThemeButton()
    let reactionsView = ReactionsView()

    #if IOS
    private let badgeView = BadgeCounterView()
    private(set) var controller: ParseConversationController?
    private var subscriptions = Set<AnyCancellable>()
    #endif
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.reactionsView)
        self.reactionsView.expressionVideoView.shouldPlay = true
        
        self.addSubview(self.button)
        let pointSize: CGFloat = 26
        
        self.button.set(style: .image(symbol: .faceSmiling,
                                      palletteColors: [.whiteWithAlpha],
                                      pointSize: pointSize,
                                      backgroundColor: .clear))
        
        self.button.isHidden = true
        
        #if IOS
        self.addSubview(self.badgeView)
        self.badgeView.minToShow = 1
        #endif
        
        self.clipsToBounds = false
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.button.expandToSuperviewSize()
        
        #if IOS
        self.reactionsView.expandToSuperviewSize()
        self.badgeView.center = CGPoint(x: self.width - 2,
                                        y: self.height - 2)
        #endif
    }
    
    func configure(with moment: Moment) {
        #if IOS
        Task { [self] in
        
            self.subscriptions.forEach { subscription in
                subscription.cancel()
            }
            
            self.controller = ParseConversationController(
                conversationID: moment.commentsId,
                automaticallySynchronize: false
            )
            try? await self.controller?.synchronize()
            let expressions = self.controller?.conversation?.expressions ?? []
            
            self.badgeView.set(value: expressions.count)
            
            if !expressions.isEmpty {
                self.reactionsView.set(expressions: expressions)
                self.reactionsView.isHidden = false
                self.button.isHidden = true
            } else {
                self.button.isHidden = false
                self.reactionsView.isHidden = true
            }
            
            self.controller?.conversationChangePublisher.mainSink(receiveValue: { [unowned self] _ in
                let expressions = self.controller?.conversation?.expressions ?? []
                self.badgeView.set(value: expressions.count)
                
                if !expressions.isEmpty {
                    self.reactionsView.set(expressions: expressions)
                    self.reactionsView.isHidden = false
                    self.button.isHidden = true
                } else {
                    self.button.isHidden = false
                    self.reactionsView.isHidden = true
                }
                
            }).store(in: &self.subscriptions)
        }
        #elseif APPCLIP
        self.button.isVisible = true 
        #endif
    }
}
