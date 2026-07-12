//
//  ReactionsFooterView.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/29/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import ScrollCounter

class StackedExpressionView: BaseView {
    
    var itemHeight: CGFloat = MessageFooterView.collapsedHeight
    
    let counter = NumberScrollCounter(value: 0,
                                      scrollDuration: Theme.animationDurationSlow,
                                      decimalPlaces: 0,
                                      prefix: "+",
                                      suffix: nil,
                                      seperator: "",
                                      seperatorSpacing: 0,
                                      font: FontType.small.font,
                                      textColor: ThemeColor.white.color,
                                      animateInitialValue: false,
                                      gradientColor: nil,
                                      gradientStop: nil)
    
    private var expressions: [ExpressionInfo] = []
    var max: Int = 3
    
    let addExpressionView = AddExpressionView()
    
    var didTapAdd: CompletionOptional = nil
    var didSelectExpression: ((ExpressionInfo) -> Void)?
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.set(backgroundColor: .B1)
        
        self.addExpressionView.didSelect { [unowned self] in
            self.didTapAdd?() 
        }
    }
    
    func configure(with message: Messageable) {
        if !self.expressions.isEmpty,
            !message.expressions.isEmpty,
           self.expressions == message.expressions {
            return
        }
                
        var expressions: [ExpressionInfo] = []
        
        self.removeAllSubviews()
        
        if message.isFromCurrentUser {
            
            if message.authorExpression.isNil {
                self.addExpressionView.configure(with: nil, showPlus: true)
                self.addSubview(self.addExpressionView)
            }
            
            expressions = message.expressions.filter { expression in
                return expression.authorId != User.current()?.objectId
            }
        
        } else {
            if message.expressions.first(where: { info in
                info.authorId == User.current()?.objectId
            }).isNil {
                self.addExpressionView.configure(with: nil, showPlus: true)
                self.addSubview(self.addExpressionView)
            }
            
            expressions = message.expressions
        }
        
        self.configure(with: expressions)
    }
    
    private func configure(with expressions: [ExpressionInfo]) {
        
        self.expressions = expressions
        
        for (index, info) in expressions.enumerated() {
            if index <= self.max - 1 {
                let view = PersonGradientView()
                view.expressionVideoView.shouldPlay = true
                view.didSelect { [unowned self] in
                    self.didSelectExpression?(info)
                }
                view.set(info: info, authorId: nil)
                self.addSubview(view)
            }
        }
        
        if expressions.count > self.max {
            let remainder = expressions.count - self.max
            self.counter.setValue(Float(remainder))
            self.addSubview(self.counter)
        }
        
        self.layoutNow()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.isVisible = self.subviews.count > 0 
        
        self.height = self.itemHeight
        
        let padding: CGFloat = Theme.ContentOffset.standard.value
        
        var xOffset: CGFloat = padding
        
        if self.addExpressionView.superview.exists {
            self.addExpressionView.squaredSize = self.height - padding
            self.addExpressionView.pin(.left, offset: .custom(padding))
            self.addExpressionView.pin(.top, offset: .custom(padding.half))
            xOffset += self.addExpressionView.right
        }
        
        var count: Int = 0
        self.subviews.forEach { view in
            if let personView = view as? PersonGradientView {
                personView.frame = CGRect(x: xOffset,
                                          y: padding.half,
                                          width: self.height - padding,
                                          height: self.height - padding)
                xOffset += view.width + padding
                count += 1
            }
        }
                 
        if count == self.max {
            self.counter.sizeToFit()
            self.counter.left = xOffset
            xOffset += self.counter.width + padding
            self.counter.centerOnY()
        } else if count == 0 {
            xOffset += padding
        }
        
        self.width = xOffset
        
        self.makeRound()
        self.clipsToBounds = false
        self.showShadow(withOffset: 0, opacity: 0.5, radius: 5, color: ThemeColor.B0.color)
    }
}
