//
//  PersonCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/24/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Contacts
import PhoneNumberKit

class PersonCell: CollectionViewManagerCell, ManageableCell {
    
    var currentItem: Person?
    
    typealias ItemType = Person

    let titleLabel = ThemeLabel(font: .system)
    let buttonTitleLabel = ThemeLabel(font: .systemBold)
    let lineView = BaseView()

    override func initializeSubviews() {
        super.initializeSubviews()

        self.contentView.addSubview(self.buttonTitleLabel)
        self.contentView.addSubview(self.titleLabel)
        self.contentView.addSubview(self.lineView)
        
        self.lineView.set(backgroundColor: .B4)
        self.lineView.alpha = 0.5
    }
    
    func configure(with item: Person) {
        if let user = item.connection?.nonMeUser {
            self.buttonTitleLabel.setText("Add")
            Task {
                await self.loadData(for: user)
            }
        } else {
            self.buttonTitleLabel.setText("Invite")
            self.titleLabel.setText(item.fullName)
            self.layoutNow()
        }
    }
    
    @MainActor
    func loadData(for user: User) async {
        guard let userWithData = try? await user.retrieveDataIfNeeded() else { return }
        self.titleLabel.setText(userWithData.fullName)
        self.layoutNow()
    }

    override func update(isSelected: Bool) {
        if let person = self.currentItem {
            if let _ = person.connection {
                if isSelected {
                    self.buttonTitleLabel.setText("Added")
                } else {
                    self.buttonTitleLabel.setText("Add")
                }
            } else {
                if isSelected {
                    self.buttonTitleLabel.setText("Added")
                } else {
                    self.buttonTitleLabel.setText("Invite")
                }
            }
        }
        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.titleLabel.setTextColor(isSelected ? .D1 : .T1)
            self.buttonTitleLabel.setTextColor(isSelected ? .D1 : .T1)
            self.setNeedsLayout()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.titleLabel.setSize(withWidth: self.contentView.width)
        self.titleLabel.centerOnY()
        self.titleLabel.pin(.left, offset: .xtraLong)
        
        self.buttonTitleLabel.setSize(withWidth: self.contentView.width)
        self.buttonTitleLabel.centerOnY()
        self.buttonTitleLabel.pin(.right, offset: .xtraLong)
        
        self.lineView.height = 1
        self.lineView.expandToSuperviewWidth()
        self.lineView.pin(.bottom)
    }
}
