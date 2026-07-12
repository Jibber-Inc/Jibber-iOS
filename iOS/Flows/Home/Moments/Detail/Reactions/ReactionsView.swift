//
//  ReactionsView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/27/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class ReactionsView: BaseView {
    
    let emotionGradientView = EmotionGradientView()
    let expressionVideoView = ReactionsVideoView()
    var cornerRadiusRatio: CGFloat = 0.25
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.insertSubview(self.emotionGradientView, at: 0)

        self.addSubview(self.expressionVideoView)
        self.expressionVideoView.layer.masksToBounds = true
        self.expressionVideoView.clipsToBounds = true

        self.set(emotionCounts: [:])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.layer.cornerRadius = self.height * self.cornerRadiusRatio

        self.emotionGradientView.expandToSuperviewSize()
        self.emotionGradientView.layer.cornerRadius = self.layer.cornerRadius

        self.expressionVideoView.expandToSuperviewSize()
        self.expressionVideoView.layer.cornerRadius = self.layer.cornerRadius
    }
    
    func getSize(forHeight height: CGFloat) -> CGSize {
        return CGSize(width: height, height: height)
    }

    func setSize(forHeight height: CGFloat) {
        self.size = self.getSize(forHeight: height)
    }

    // MARK: - Open setters
    
    /// The currently running task that is loading the expression.
    private var loadTask: Task<Void, Never>?
    
    func set(expressions: [ExpressionInfo], defaultColors: [ThemeColor] = [.B0, .B6]) {
        
        self.loadTask?.cancel()
        
        self.loadTask = Task { [weak self] in
            guard let self else { return }
            
            var all: [Expression] = []
            
            await expressions.asyncForEach { info in
                guard !Task.isCancelled else { return }
                
                if let expression = try? await Expression.getObject(with: info.expressionId) {
                    all.append(expression)
                }
            }

            self.expressionVideoView.expressions = all
        }
    }
    
    func set(emotionCounts: [Emotion: Int], defaultColors: [ThemeColor] = [.B0, .B6]) {
        self.emotionGradientView.defaultColors = defaultColors
        let last = self.emotionGradientView.set(emotionCounts: emotionCounts).last
                
        self.layer.borderWidth = 2
        self.layer.borderColor = last?.withAlphaComponent(0.9).cgColor
        self.layer.masksToBounds = false
        
        self.setNeedsLayout()
    }
}
