//
//  AchievementCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/18/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

struct AchievementViewModel: Hashable {
    var type: AchievementType
    var count: Int {
        return self.achievements.count
    }
    
    var achievements: [Achievement] = []
}

class AchievementCell: CollectionViewManagerCell, ManageableCell {
    
    typealias ItemType = AchievementViewModel
    
    var currentItem: AchievementViewModel?
    
    private let badgeView = BadgeDetailView()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.contentView.addSubview(self.badgeView)
    }
    
    func configure(with item: AchievementViewModel) {
        self.currentItem = item
        self.badgeView.configure(with: item)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let padding = Theme.ContentOffset.xtraLong.value
        self.badgeView.width = self.contentView.width - padding.doubled - Theme.ContentOffset.long.value
        self.badgeView.height = self.contentView.height - padding.doubled
        self.badgeView.centerOnXAndY()
    }
}

private class BadgeDetailView: BaseView {
    
    private let badgeView = BadgeView()
    private let label = ThemeLabel(font: .small)
    private let bottomLabel = ThemeLabel(font: .xtraSmall)
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.badgeView)
        self.addSubview(self.label)
        self.label.textAlignment = .center
        self.label.alpha = 0.5
        
        self.addSubview(self.bottomLabel)
        self.label.textAlignment = .center
        self.label.alpha = 0.0
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.badgeView.expandToSuperviewWidth()
        self.badgeView.height = self.height - 30
        self.badgeView.pin(.top)
        
        self.label.setSize(withWidth: self.width + 40)
        self.label.pin(.bottom)
        self.label.centerOnX()
        
        self.bottomLabel.setSize(withWidth: self.width + 40)
        self.bottomLabel.match(.top, to: .bottom, of: self.label, offset: .short)
        self.bottomLabel.centerOnX()
    }
    
    func configure(with model: AchievementViewModel) {
        self.badgeView.configure(with: model)
        self.label.setText(model.type.title)
        
        if let firstDate = model.achievements.first?.createdAt {
            self.label.alpha = 1.0
            self.bottomLabel.setText(Date.monthDayYear.string(from: firstDate))
            self.bottomLabel.alpha = 0.5
        } else {
            self.bottomLabel.alpha = 0.0
            self.label.alpha = 0.5
        }
        
        self.setNeedsLayout()
    }
}
