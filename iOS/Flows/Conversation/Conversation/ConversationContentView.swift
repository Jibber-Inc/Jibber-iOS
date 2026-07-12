//
//  ConversationContentView.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/6/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

@MainActor
class ConversationContentView: BaseView {

    let stackedAvatarView = StackedAvatarView()
    let label = ThemeLabel(font: .medium, textColor: .textColor)
    let messageLabel = ThemeLabel(font: .regularBold, textColor: .textColor)

    private var cancellables = Set<AnyCancellable>()
    private(set) var currentItem: Conversation?

    deinit {
        self.cancellables.forEach { cancellable in
            cancellable.cancel()
        }
    }

    override func initializeSubviews() {
        super.initializeSubviews()

        self.set(backgroundColor: .white)

        self.addSubview(self.stackedAvatarView)
        self.addSubview(self.label)
        self.addSubview(self.messageLabel)
        self.label.textAlignment = .left
        self.label.lineBreakMode = .byTruncatingTail

        self.messageLabel.textAlignment = .left
        self.messageLabel.lineBreakMode = .byTruncatingTail

        self.stackedAvatarView.itemHeight = 70
    }

    func configure(with item: Conversation) {
        if self.currentItem?.title != item.title {
            self.label.setText(item.title)
        }

        if self.currentItem?.lastActiveMembers != item.lastActiveMembers {
            let members = item.lastActiveMembers.filter { member in
                return member.id != User.current()?.objectId
            }

            if !members.isEmpty {
                self.stackedAvatarView.set(items: members)
            } else {
                self.stackedAvatarView.set(items: [User.current()!])
            }

            self.stackedAvatarView.layoutNow()
        }

        if self.currentItem?.latestMessages.first != item.latestMessages.first {
            if let msg = item.latestMessages.first {
                self.messageLabel.setText(msg.text)
            }
        }

        self.layoutNow()

        self.currentItem = item
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.stackedAvatarView.setSize()
        self.stackedAvatarView.centerOnY()
        self.stackedAvatarView.pin(.left, offset: .standard)

        let maxWidth = self.width - Theme.contentOffset - self.stackedAvatarView.width
        self.label.setSize(withWidth: maxWidth)
        self.label.pin(.top, offset: .standard)
        self.label.match(.left, to: .right, of: self.stackedAvatarView, offset: .standard)

        let maxHeight = self.height - self.label.height - Theme.contentOffset
        self.messageLabel.setSize(withWidth: maxWidth, height: maxHeight)
        self.messageLabel.match(.top, to: .bottom, of: self.label, offset: .short)
        self.messageLabel.match(.left, to: .left, of: self.label)
    }
}
