//
//  ConversationViewControllerDataSource.swift
//  ConversationViewControllerDataSource
//
//  Created by Martin Young on 9/15/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

typealias ConversationSection = ConversationCollectionViewDataSource.SectionType
typealias ConversationItem = ConversationCollectionViewDataSource.ItemType

@MainActor
class ConversationCollectionViewDataSource: CollectionViewDataSource<ConversationSection,
                                            ConversationItem> {

    /// Model for the main section of the conversation.
    struct SectionType: Hashable { }

    enum ItemType: Hashable {
        case conversation(String)
    }

    // Input handling
    weak var messageContentDelegate: MessageContentDelegate?
    var handleCollectionViewTapped: CompletionOptional = nil
    var handleAddPeopleSelected: CompletionOptional = nil

    /// The conversation ID of the conversation that is preparing to send, if any.
    private var conversationPreparingToSend: String?

    // Cell registration
    private let conversationCellRegistration
    = ConversationCollectionViewDataSource.createConversationCellRegistration()
    
    var uiState: ConversationUIState = .read

    nonisolated override func dequeueCell(with collectionView: UICollectionView,
                                           indexPath: IndexPath,
                                           section: SectionType,
                                           item: ItemType) -> UICollectionViewCell? {
        MainActor.assumeIsolated {
            switch item {
            case .conversation(let cid):
                let conversationCell
                = collectionView.dequeueConfiguredReusableCell(using: self.conversationCellRegistration,
                                                               for: indexPath,
                                                               item: (cid, self.uiState, self))
                conversationCell.messageContentDelegate = self.messageContentDelegate
                conversationCell.handleCollectionViewTapped = { [unowned self] in
                    self.handleCollectionViewTapped?()
                }
                conversationCell.handleAddMembersTapped = { [unowned self] in
                    self.handleAddPeopleSelected?()
                }

                return conversationCell
            }
        }
    }

    /// Updates the datasource with to reflect the conversation controller.
    func update(with conversationController: ParseConversationController) async {
        let updatedSnapshot = self.updatedSnapshot(with: conversationController)
        await self.apply(updatedSnapshot)
    }

    func updatedSnapshot(with conversationController: ParseConversationController)
    -> NSDiffableDataSourceSnapshot<ConversationSection, ConversationItem> {

        var snapshot = self.snapshot()

        let sectionID = ConversationSection()

        var updatedItems: [ConversationItem] = []
        if let conversation = conversationController.conversation {
            updatedItems.append(ConversationItem.conversation(conversation.id))
        }

        snapshot.setItems(updatedItems, in: sectionID)

        return snapshot
    }

    func set(conversationPreparingToSend: String?) {
        self.conversationPreparingToSend = conversationPreparingToSend

        self.reconfigureAllItems()
    }
}

// MARK: - Cell Registration

extension ConversationCollectionViewDataSource {

    typealias ConversationCellRegistration
    = UICollectionView.CellRegistration<ConversationMessagesCell,
                                        (conversationId: String,
                                         uiState: ConversationUIState,
                                         dataSource: ConversationCollectionViewDataSource)>

    static func createConversationCellRegistration() -> ConversationCellRegistration {
        return ConversationCellRegistration { cell, indexPath, item in
            let conversationController = JibberMessagingClient.shared.conversationController(for: item.conversationId)

            let isPreparedToSend = conversationController?.conversation?.id == item.dataSource.conversationPreparingToSend
            if let conversation = conversationController?.conversation {
                cell.set(conversation: conversation, shouldPrepareToSend: isPreparedToSend)
            }
            
            cell.set(state: item.uiState)
        }
    }
}
