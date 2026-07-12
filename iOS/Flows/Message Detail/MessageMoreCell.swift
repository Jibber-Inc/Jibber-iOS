//
//  MessageMoreCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/29/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

struct MoreOptionModel: Hashable {
    var conversationId: String
    var messageId: String
    var option: MessageDetailDataSource.OptionType
}

class MessageMoreCell: CollectionViewManagerCell, ManageableCell {
    
    typealias ItemType = MoreOptionModel
    
    var currentItem: MoreOptionModel?
    
    let imageView = UIImageView()
    let label = ThemeLabel(font: .small)
    let button = ThemeButton()
    
    var didTapEdit: CompletionOptional = nil
    var didTapDelete: CompletionOptional = nil
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.contentView.set(backgroundColor: .B6)
        self.contentView.addSubview(self.imageView)
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.tintColor = ThemeColor.white.color
        self.contentView.addSubview(self.label)
        self.label.textAlignment = .center
        
        self.contentView.addSubview(self.button)
        self.button.showsMenuAsPrimaryAction = true 
        
        self.contentView.layer.borderColor = ThemeColor.BORDER.color.cgColor
        self.contentView.layer.borderWidth = 0.5
        self.contentView.layer.cornerRadius = Theme.cornerRadius
    }
    
    func configure(with item: MoreOptionModel) {
        self.imageView.image = item.option.image
        self.label.setText(item.option.title)
        guard let message = MessageController.controller(for: item.conversationId, messageId: item.messageId)?.message else { return }
        self.button.menu = self.makeContextMenu(for: message)
        self.setNeedsLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.imageView.squaredSize = self.height * 0.3
        self.imageView.centerOnX()
        self.imageView.bottom = self.contentView.centerY + 6
        
        self.label.setSize(withWidth: self.contentView.width)
        self.label.centerOnX()
        self.label.match(.top, to: .bottom, of: self.imageView, offset: .standard)
        
        self.button.expandToSuperviewSize()
    }
    
    private func makeContextMenu(for message: Messageable) -> UIMenu {

        let neverMind = UIAction(title: "Never Mind", image: ImageSymbol.noSign.image) { action in }

        let confirmDelete = UIAction(title: "Confirm",
                                     image: ImageSymbol.trash.image,
                                     attributes: .destructive) { action in
            self.didTapDelete?()
        }

        let deleteMenu = UIMenu(title: "Delete",
                                image: ImageSymbol.trash.image,
                                options: .destructive,
                                children: [confirmDelete, neverMind])

        let edit = UIAction(title: "Edit",
                            image: ImageSymbol.pencil.image) { [unowned self] action in
            self.didTapEdit?()
        }

        let read = UIAction(title: "Set to read",
                            image: ImageSymbol.eyeglasses.image) { [unowned self] action in
            self.setToRead(with: message)
        }

        let unread = UIAction(title: "Set to unread",
                              image: ImageSymbol.eyeglasses.image) { [unowned self] action in
            self.setToUnread(with: message)
        }

        var menuElements: [UIMenuElement] = []

        if message.isFromCurrentUser {
            menuElements.append(deleteMenu)
        }

        if message.isFromCurrentUser {
            menuElements.append(edit)
        }

        if message.isConsumedByMe {
            menuElements.append(unread)
        } else if message.canBeConsumed {
            menuElements.append(read)
        }

        return UIMenu.init(title: "More",
                           image: nil,
                           identifier: nil,
                           options: [],
                           children: menuElements)
    }
    
    // MARK: - Message Consumption

    func setToRead(with message: Messageable) {
        guard message.canBeConsumed else { return }
        Task {
            await message.setToConsumed()
        }
    }

    func setToUnread(with message: Messageable) {
        guard message.isConsumedByMe else { return }
        Task {
            do {
                try await message.setToUnconsumed()
            } catch {
                logError(error)
            }
        }
    }

}
