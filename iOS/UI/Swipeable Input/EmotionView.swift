//
//  EmotionView.swift
//  Jibber
//
//  Created by Benji Dodgson on 12/13/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit
import StreamChat

class EmotionView: BaseView {
    
    let emojiContainer = BaseView()
    let emojiLabel = ThemeLabel(font: .reactionEmoji)
    
    let label = ThemeLabel(font: .small)
    let button = ThemeButton()
    
    var didSelectEmotion: ((Emotion) -> Void)?
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.emojiContainer)
        self.emojiContainer.addSubview(self.emojiLabel)
        
        self.addSubview(self.label)
        self.addSubview(self.button)
        
        self.clipsToBounds = false
        
        self.button.showsMenuAsPrimaryAction = true
    }
    
    func configure(for message: Messageable) {
        let controller = ChatClient.shared.messageController(for: message)
        if let data = controller?.message?.extraData["emotions"] {
            switch data {
            case .array(let emotions):
                if let first = emotions.first {
                    switch first {
                    case .string(let value):
                        if let emotion = Emotion.init(rawValue: value) {
                            self.isVisible = true
                            self.configure(for: emotion)
                        } else {
                            self.isVisible = false 
                        }
                    default:
                        self.isVisible = false
                    }
                } else {
                    self.isVisible = false
                }
            default:
                self.isVisible = false
            }
        } else {
            self.isVisible = false
        }
    }
    
    func configure(for emotion: Emotion) {
        self.emojiLabel.setText(emotion.emoji)
        self.label.setText(emotion.rawValue.firstCapitalized)
        self.button.menu = self.createMenu(for: emotion)
        self.layoutNow()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.emojiLabel.setSize(withWidth: self.width)
        self.label.setSize(withWidth: 200)
        
        self.emojiContainer.expandToSuperviewHeight()
        self.emojiContainer.width = self.emojiLabel.width + Theme.ContentOffset.short.value.doubled
        self.emojiLabel.centerOnXAndY()
        
        self.height = MessageDetailView.height 
        self.width = self.emojiContainer.width + Theme.ContentOffset.short.value + self.label.width + Theme.ContentOffset.short.value.doubled
        
        self.pin(.left)
        
        self.emojiContainer.pin(.left)
        self.emojiContainer.pin(.top)
        
        self.label.centerOnY()
        self.label.match(.left, to: .right, of: self.emojiContainer, offset: .short)
        
        self.button.expandToSuperviewWidth()
        self.button.height = 36
        self.button.centerOnXAndY()
    }
    
    private func createMenu(for emotion: Emotion) -> UIMenu {
        
        var children: [UIMenuElement] = []
        Emotion.allCases.forEach { e in
            let state: UIMenuElement.State = e == emotion ? .on : .off
            let title = "\(e.emoji) \(e.rawValue.capitalized)"
            let action = UIAction(title: title,
                                  image: nil,
                                  identifier: nil,
                                  discoverabilityTitle: nil,
                                  attributes: [],
                                  state: state) { [unowned self] _ in
                self.didSelectEmotion?(e)
                self.configure(for: e)
            }
            children.append(action)
        }
        
        return UIMenu(title: "I'm feeling...",
                      image: nil,
                      identifier: nil,
                      options: [.singleSelection],
                      children: children)
    }
}
