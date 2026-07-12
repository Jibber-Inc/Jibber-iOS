//
//  ConversationInfoCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/21/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

class ConversationInfoCell: CollectionViewManagerCell, ManageableCell {
    
    var currentItem: String?

    private let topicLabel = ThemeLabel(font: .mediumBold)
    private let dateLabel = ThemeLabel(font: .small)
    
    private var controller: ParseConversationController?

    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.contentView.addSubview(self.topicLabel)
        self.contentView.addSubview(self.dateLabel)
        self.dateLabel.alpha = 0.25
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.topicLabel.setSize(withWidth: self.width)
        self.topicLabel.pin(.left)
        self.topicLabel.pin(.top, offset: .long)

        self.dateLabel.setSize(withWidth: self.width)
        self.dateLabel.pin(.left)
        self.dateLabel.pin(.bottom, offset: .short)
    }
    
    func configure(with item: String) {
        self.cancellables.removeAll()
        self.controller = ParseConversationController.controller(for: item)
        self.subscribeToUpdates()

        if let conversation = self.controller?.conversation {
            Task {
                await self.update(with: conversation)
            }
        }
    }
    
    @MainActor
    private func update(with conversation: ParseConversation) async {
        let dateString = Date.monthDayYear.string(from: conversation.createdAt)

        let creator = await PeopleStore.shared.getPerson(withPersonId: conversation.authorId)
        let creatorName = creator?.givenName ?? "Unknown"

        self.dateLabel.setText("Created by \(creatorName) on \(dateString)")
        self.setTopic(for: conversation)
        
        self.layoutNow()
    }
    
    private func setTopic(for conversation: ParseConversation) {
        if let title = conversation.title {
            self.topicLabel.setText(title)
        } else {
            // If there is no title, then list the members of the conversation.
            let members = conversation.lastActiveMembers.filter { member in
                return !member.isCurrentUser
            }

            var membersString = ""
            members.forEach { member in
                if membersString.isEmpty {
                    membersString = member.givenName
                } else {
                    membersString.append(", \(member.givenName)")
                }
            }
            
            if membersString.isEmpty {
                self.topicLabel.setText("No Topic")
            } else {
                self.topicLabel.setText(membersString)
            }
        }
    }
    
    private func subscribeToUpdates() {
        self.controller?
            .conversationChangePublisher
            .mainSink { [weak self] event in
                switch event {
                case .create(let conversation), .update(let conversation):
                    Task { [weak self] in
                        await self?.update(with: conversation)
                    }
                case .remove(_):
                    self?.topicLabel.setText(nil)
                    self?.dateLabel.setText(nil)
                }
            }.store(in: &self.cancellables)
    }
}
