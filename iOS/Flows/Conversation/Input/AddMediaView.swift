//
//  AddAttachmentView.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/18/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class AddMediaView: ThemeButton {
    
    let plusImageView = UIImageView()
    let displayableImageView = DisplayableImageView()
    
    var didSelectRemove: CompletionOptional = nil
        
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.set(backgroundColor: .gray)
        
        self.addSubview(self.plusImageView)
        self.plusImageView.image = UIImage(systemName: "plus")
        self.plusImageView.tintColor = UIColor.white.withAlphaComponent(0.8)
        
        self.layer.borderColor = ThemeColor.gray.color.cgColor
        self.layer.borderWidth = 2
        self.layer.masksToBounds = true
        self.layer.cornerRadius = Theme.innerCornerRadius
                
        self.addSubview(self.displayableImageView)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.displayableImageView.expandToSuperviewSize()
        
        self.plusImageView.squaredSize = self.height * 0.5
        self.plusImageView.centerOnXAndY()
    }
    
    func configure(with item: MediaItem?) {
        self.displayableImageView.isHidden = item.isNil
        self.displayableImageView.displayable = item
        self.updateMenu(for: item)
    }
    
    private func updateMenu(for item: MediaItem?) {
        if let item = item {
            self.menu = self.createMenu(for: item)
        } else {
            self.menu = nil
        }
    }
    
    private func createMenu(for item: MediaItem) -> UIMenu {
        
        let remove = UIAction(title: "Remove",
                              image: UIImage(systemName: "trash"),
                              attributes: .destructive) { action in
            self.didSelectRemove?()
        }

        return UIMenu.init(title: "",
                           image: nil,
                           identifier: nil,
                           options: [],
                           children: [remove])
    }
}