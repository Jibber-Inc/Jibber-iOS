//
//  EmotionCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/27/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class EmotionCell: CollectionViewManagerCell, ManageableCell {
    typealias ItemType = Emotion
    
    var currentItem: Emotion?
    
    func configure(with item: Emotion) {
        self.setNeedsUpdateConfiguration()
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        
        // Create new configuration object and update it base on state
        var newConfiguration = EmotionContentConfiguration().updated(for: state)
        
        // Update any configuration parameters related to data item
        newConfiguration.emotion = self.currentItem
        
        // Set content configuration in order to update custom content view
        self.contentConfiguration = newConfiguration
    }
}

class EmotionContentView: BaseView, UIContentView {
    
    private var currentConfiguration: EmotionContentConfiguration!
    
    var configuration: UIContentConfiguration {
        get {
            return self.currentConfiguration
        }
        set {
            guard let newConfiguration = newValue as? EmotionContentConfiguration else {
                return
            }
            
            self.apply(configuration: newConfiguration)
        }
    }
    
    private let label = ThemeLabel(font: .regular)
    private let borderView = BaseView()
    
    init(configuration: EmotionContentConfiguration) {
        super.init()
        self.loadViews()
        self.apply(configuration: configuration)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    private func loadViews() {
        
        self.addSubview(self.borderView)
        self.borderView.translatesAutoresizingMaskIntoConstraints = false
        
        self.addSubview(self.label)
        self.label.textAlignment = .center
        
        self.label.translatesAutoresizingMaskIntoConstraints = false
        let inset = Theme.ContentOffset.long.value
        
        NSLayoutConstraint.activate([
            self.label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: inset),
            self.label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -inset),
            self.borderView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 4),
            self.borderView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -4),
            self.borderView.heightAnchor.constraint(equalTo: self.heightAnchor)
        ])
    }
    
    private func apply(configuration: EmotionContentConfiguration) {

        guard self.currentConfiguration != configuration else {
            return
        }
        
        self.currentConfiguration = configuration
        
        guard let emotion = configuration.emotion else { return }
                
        self.updateLayout(with: emotion, isSelected: configuration.isSelected)
    }
    
    private func updateLayout(with item: Emotion, isSelected: Bool) {
        let color = item.color

        self.label.setText(item.rawValue)
        self.label.textColor = color 
        
        self.borderView.layer.borderColor = isSelected ? color.cgColor : color.withAlphaComponent(0.2).cgColor 
        self.borderView.layer.borderWidth = 2
        self.borderView.layer.cornerRadius = Theme.innerCornerRadius
        self.borderView.layer.masksToBounds = false
        
        self.borderView.backgroundColor = isSelected ? color.withAlphaComponent(0.2) : .clear
    }
}

struct EmotionContentConfiguration: UIContentConfiguration, Hashable {
    
    var emotion: Emotion?
    var isSelected: Bool = false
    
    func makeContentView() -> UIView & UIContentView {
        return EmotionContentView(configuration: self)
    }
    
    func updated(for state: UIConfigurationState) -> EmotionContentConfiguration {
        guard let state = state as? UICellConfigurationState else { return self }
        var updatedConfig = self
        updatedConfig.isSelected = state.isSelected || state.isHighlighted
        return updatedConfig

    }
}