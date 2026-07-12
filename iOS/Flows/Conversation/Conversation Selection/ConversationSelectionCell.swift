//
//  MemberSelectionCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/20/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Combine
import Foundation

class ConversationSelectionCell: CollectionViewManagerCell, ManageableCell {
    
    var currentItem: String?
    
    typealias ItemType = String

    let stackedPersonView = StackedPersonView()
    let titleLabel = ThemeLabel(font: .regular)
    private(set) var conversationController: ParseConversationController?
    private var subscriptions = Set<AnyCancellable>()
    
    override func initializeSubviews() {
        super.initializeSubviews()

        self.stackedPersonView.itemHeight = 30
        self.stackedPersonView.max = 5
        self.contentView.addSubview(self.stackedPersonView)
        self.contentView.addSubview(self.titleLabel)
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.roundCorners()
    }
    
    func configure(with item: String) {
        self.taskPool.cancelAndRemoveAll()
        self.subscriptions.removeAll()

        Task { @MainActor [weak self] in
            guard let self else { return }

            let controller: ParseConversationController
            if let current = self.conversationController,
               current.conversationID.rawValue == item {
                controller = current
            } else {
                controller = ParseConversationController(
                    conversationID: item,
                    automaticallySynchronize: false
                )
                self.conversationController = controller
            }

            do {
                try await controller.synchronize(pageSize: 1)
            } catch {
                logError(error)
            }

            guard !Task.isCancelled,
                  self.conversationController === controller else { return }
            self.subscribeToUpdates()
            self.refreshVisibleState()
        }.add(to: self.taskPool)
    }

    private func subscribeToUpdates() {
        self.conversationController?
            .conversationChangePublisher
            .mainSink { [weak self] _ in
                self?.refreshVisibleState()
            }.store(in: &self.subscriptions)

        self.conversationController?
            .membersChangesPublisher
            .mainSink { [weak self] _ in
                self?.refreshVisibleState()
            }.store(in: &self.subscriptions)
    }

    @MainActor
    private func refreshVisibleState() {
        guard let conversation = self.conversationController?.conversation else { return }

        let members = conversation.lastActiveMembers.filter {
            $0.personId != User.current()?.objectId
        }
        self.titleLabel.setText(conversation.title)
        self.stackedPersonView.configure(with: members)
        self.layoutNow()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.taskPool.cancelAndRemoveAll()
        self.subscriptions.removeAll()
        self.conversationController = nil
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.stackedPersonView.pin(.left, offset: .standard)
        self.stackedPersonView.centerOnY()
        
        let maxWidth = self.contentView.width - self.stackedPersonView.width - Theme.ContentOffset.standard.value.doubled - Theme.ContentOffset.standard.value
        self.titleLabel.setSize(withWidth: maxWidth, height: self.contentView.height)
        self.titleLabel.match(.left, to: .right, of: self.stackedPersonView, offset: .standard)
        self.titleLabel.centerOnY()
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        // Get the system default background configuration for a plain style list cell in the current state.
        var backgroundConfig = UIBackgroundConfiguration.listPlainCell().updated(for: state)

        // Customize the background color to be clear, no matter the state.
        backgroundConfig.backgroundColor = ThemeColor.clear.color
        
        // Apply the background configuration to the cell.
        self.backgroundConfiguration = backgroundConfig
        
        if state.isHighlighted || state.isSelected {
            Task {
                await UIView.awaitAnimation(with: .fast) {
                    self.contentView.set(backgroundColor: .D6)
                }
            }
            if state.isHighlighted {
                self.selectionImpact.impactOccurred(intensity: 1.0)
            }
        } else {
            Task {
                await UIView.awaitAnimation(with: .fast) {
                    self.contentView.backgroundColor = .clear
                }
            }
        }
    }
}
