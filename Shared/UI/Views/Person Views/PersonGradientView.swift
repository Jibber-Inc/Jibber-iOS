//
//  PersonGradientView.swift
//  Jibber
//
//  Created by Benji Dodgson on 4/28/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class PersonGradientView: DisplayableImageView {
    
    let emotionGradientView = EmotionGradientView()
    let expressionVideoView = ExpressionVideoView()
    var cornerRadiusRatio: CGFloat = 0.25
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.insertSubview(self.emotionGradientView, at: 0)

        self.addSubview(self.expressionVideoView)
        self.expressionVideoView.layer.masksToBounds = true
        self.expressionVideoView.clipsToBounds = true

        self.set(emotionCounts: [:])
        self.subscribeToUpdates()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.layer.cornerRadius = self.height * self.cornerRadiusRatio

        self.emotionGradientView.expandToSuperviewSize()
        self.emotionGradientView.layer.cornerRadius = self.layer.cornerRadius

        self.expressionVideoView.expandToSuperviewSize()
        self.expressionVideoView.layer.cornerRadius = self.layer.cornerRadius
        
        self.imageView.layer.cornerRadius = self.layer.cornerRadius
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
    
    func set(info: ExpressionInfo?,
             authorId: String?,
             defaultColors: [ThemeColor] = [.B0, .B6]) {
        
        self.loadTask?.cancel()
        
        self.loadTask = Task { [weak self] in
            guard let self else { return }

            var expression: Expression?
            if let expressionId = info?.expressionId {
                expression = try? await Expression.getObject(with: expressionId)
            }

            guard !Task.isCancelled else { return }

            var person: PersonType?
            if expression.isNil, let authorId = authorId {
                person = await PeopleStore.shared.getPerson(withPersonId: authorId)
            }

            guard !Task.isCancelled else { return }

            self.set(expression: expression, person: person)
        }
    }
    
    func set(expression: Expression?, person: PersonType?) {
        self.expressionVideoView.expression = expression
        self.expressionVideoView.isVisible = expression.exists
        self.imageView.isVisible = expression.isNil

        if let expression = expression {
            self.set(displayable: nil)
            self.set(emotionCounts: expression.emotionCounts)
        } else if let person = person {
            self.set(displayable: person)
            self.imageView.isVisible = true
            self.set(emotionCounts: [:])
        }
        
        self.blurView.isHidden = true

        self.setNeedsLayout()
    }

    func set(displayable: ImageDisplayable?) {
        self.displayable = displayable
    }
    
    func set(emotionCounts: [Emotion: Int], defaultColors: [ThemeColor] = [.B0, .B6]) {
        self.emotionGradientView.defaultColors = defaultColors
        let last = self.emotionGradientView.set(emotionCounts: emotionCounts).last
                
        self.layer.borderWidth = 2
        self.layer.borderColor = last?.withAlphaComponent(0.9).cgColor
        self.layer.masksToBounds = false
        
        self.setNeedsLayout()
    }
    
    // MARK: - Subscriptions

    /// Called when the currently assigned person receives an update to their state.
    func didRecieveUpdateFor(person: PersonType) {
        self.displayable = person
    }

    private func subscribeToUpdates() {
        PeopleStore.shared.$personUpdated
            .filter { [unowned self] updatedPerson in
                // Only handle person updates related to the currently assigned person.
                if let person = self.displayable as? PersonType {
                    return person.personId == updatedPerson?.personId
                } else {
                    return false
                }
            }.mainSink { [unowned self] updatedPerson in
                guard let updatedPerson = updatedPerson else { return }
                self.didRecieveUpdateFor(person: updatedPerson)
            }.store(in: &self.cancellables)
    }
}
