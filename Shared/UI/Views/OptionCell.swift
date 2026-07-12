//
//  OptionCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/24/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

protocol OptionDisplayable {
    @MainActor var image: UIImage? { get }
    var title: String { get }
    var color: ThemeColor { get }
}

extension OptionDisplayable {
    var color: ThemeColor {
        return .white
    }
}

class OptionCell: CollectionViewManagerCell {
        
    private let imageView = UIImageView()
    private let label = ThemeLabel(font: .regular)
    let lineView = BaseView()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.contentView.addSubview(self.imageView)
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.tintColor = ThemeColor.white.color
        
        self.contentView.addSubview(self.label)
        
        self.contentView.addSubview(self.lineView)
        self.lineView.set(backgroundColor: .white)
        self.lineView.alpha = 0.1
    }
    
    func configureFor(option: OptionDisplayable) {
        self.imageView.image = option.image
        self.imageView.tintColor = option.color.color
        self.label.setText(option.title)
        self.label.setTextColor(option.color)
        self.layoutNow()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.imageView.squaredSize = 20
        self.imageView.centerOnY()
        self.imageView.pin(.right)
        
        self.label.setSize(withWidth: self.contentView.width)
        self.label.centerOnY()
        self.label.pin(.left)
        
        self.lineView.expandToSuperviewWidth()
        self.lineView.height = 1
        self.lineView.pin(.bottom)
    }
}
