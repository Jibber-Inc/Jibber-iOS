//
//  ConversationViewControllerDataSource.swift
//  ConversationViewControllerDataSource
//
//  Created by Martin Young on 9/15/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat

typealias ConversationSection = ConversationCollectionViewDataSource.SectionType
typealias ConversationItem = ConversationCollectionViewDataSource.ItemType

class ConversationCollectionViewDataSource: CollectionViewDataSource<ConversationSection,
                                            ConversationItem> {

    /// Model for the main section of the conversation or thread.
    /// The parent message is root message that has replies in a thread. It is nil for a conversation.
    struct SectionType: Hashable {
        let sectionID: String
        let conversationsController: ConversationListController?
        let parentMessageID: MessageId?

        var isConversationList: Bool { return self.conversationsController.exists }
        var isThread: Bool { return self.parentMessageID.exists }

        init(sectionID: String,
             conversationsController: ConversationListController? = nil,
             parentMessageID: MessageId? = nil) {

            self.sectionID = sectionID
            self.conversationsController = conversationsController
            self.parentMessageID = parentMessageID
        }
    }

    enum ItemType: Hashable {
        case messages(String)
        case loadMore
    }

    var handleSelectedConversation: ((MessageSequence) -> Void)?
    var handleDeletedConversation: ((MessageSequence) -> Void)?

    var handleSelectedMessage: ((Messageable) -> Void)?
    var handleDeleteMessage: ((Messageable) -> Void)?
    var handleLoadMoreMessages: CompletionOptional = nil
    @Published var conversationUIState: ConversationUIState = .read

    // Cell registration
    private let messageCellRegistration = ConversationCollectionViewDataSource.createMessageCellRegistration()
    private let conversationCellRegistration
    = ConversationCollectionViewDataSource.createConversationCellRegistration()
    private let threadMessageCellRegistration
    = ConversationCollectionViewDataSource.createThreadMessageCellRegistration()
    private let loadMoreMessagesCellRegistration
    = ConversationCollectionViewDataSource.createLoadMoreCellRegistration()

    override func dequeueCell(with collectionView: UICollectionView,
                              indexPath: IndexPath,
                              section: SectionType,
                              item: ItemType) -> UICollectionViewCell? {

        switch item {
        case .messages(let itemID):
            if section.isThread {
                let cid = try! ConversationID(cid: section.sectionID)
                let threadCell
                = collectionView.dequeueConfiguredReusableCell(using: self.threadMessageCellRegistration,
                                                               for: indexPath,
                                                               item: (cid, itemID, self))

                threadCell.handleDeleteMessage = { [unowned self] (message) in
                    self.handleDeleteMessage?(message)
                }
                return threadCell
            } else if section.isConversationList {
                let cid = try! ConversationID(cid: itemID)

                let messageCell
                = collectionView.dequeueConfiguredReusableCell(using: self.conversationCellRegistration,
                                                               for: indexPath,
                                                               item: (cid, self))
                messageCell.handleTappedConversation = { [unowned self] (conversation) in
                    self.handleSelectedConversation?(conversation)
                }
                messageCell.handleDeleteConversation = { [unowned self] (conversation) in
                    self.handleDeletedConversation?(conversation)
                }
                return messageCell
            } else {
                let cid = try! ConversationID(cid: section.sectionID)
                let messageCell
                = collectionView.dequeueConfiguredReusableCell(using: self.messageCellRegistration,
                                                               for: indexPath,
                                                               item: (cid, itemID, self))
                messageCell.handleTappedConversation = { [unowned self] (conversation) in
                    self.handleSelectedConversation?(conversation)
                }
                messageCell.handleDeleteConversation = { [unowned self] (conversation) in
                    self.handleDeletedConversation?(conversation)
                }
                return messageCell
            }
        case .loadMore:
            let loadMoreCell
            = collectionView.dequeueConfiguredReusableCell(using: self.loadMoreMessagesCellRegistration,
                                                           for: indexPath,
                                                           item: String())
            loadMoreCell.handleLoadMoreMessages = { [unowned self] in
                self.handleLoadMoreMessages?()
            }
            return loadMoreCell
        }
    }

    /// Updates the datasource with the passed in array of message changes.
    func update(with changes: [ListChange<Message>],
                conversationController: ConversationControllerType,
                collectionView: UICollectionView) async {

        let conversation = conversationController.conversation

        var snapshot = self.snapshot()

        let sectionID = ConversationSection(sectionID: conversation.cid.description,
                                            parentMessageID: conversationController.rootMessage?.id)

        // If there's more than one change, reload all of the data.
        guard changes.count == 1 else {
            snapshot.deleteItems(snapshot.itemIdentifiers(inSection: sectionID))
            snapshot.appendItems(conversationController.messages.asConversationCollectionItems,
                                 toSection: sectionID)
            if !conversationController.hasLoadedAllPreviousMessages {
                snapshot.appendItems([.loadMore], toSection: sectionID)
            }
            await self.apply(snapshot)
            return
        }

        // If this gets set to true, we should scroll to the most recent message after applying the snapshot
        var scrollToLatestMessage = false

        for change in changes {
            switch change {
            case .insert(let message, let index):
                snapshot.insertItems([.messages(message.id)],
                                     in: sectionID,
                                     atIndex: index.item)
                if message.isFromCurrentUser {
                    scrollToLatestMessage = true
                }
            case .move:
                snapshot.deleteItems(snapshot.itemIdentifiers(inSection: sectionID))
                snapshot.appendItems(conversationController.messages.asConversationCollectionItems,
                                     toSection: sectionID)
            case .update(let message, _):
                #warning("This can crash the app")
                snapshot.reconfigureItems([message.asConversationCollectionItem])
            case .remove(let message, _):
                snapshot.deleteItems([message.asConversationCollectionItem])
            }
        }

        // Only show the load more cell if there are previous messages to load.
        snapshot.deleteItems([.loadMore])
        if !conversationController.hasLoadedAllPreviousMessages {
            snapshot.appendItems([.loadMore], toSection: sectionID)
        }

        await Task.onMainActorAsync { [snapshot = snapshot, scrollToLatestMessage = scrollToLatestMessage] in
            self.apply(snapshot)

            // Scroll to the latest message if needed and reconfigure cells as needed.
            if scrollToLatestMessage, let sectionIndex = snapshot.indexOfSection(sectionID) {
                let latestMessageIndex = IndexPath(item: 0, section: sectionIndex)
                if sectionID.isThread {
                    // Inserting a message can cause the visual state of the previous message to change.
                    self.reconfigureItem(atIndex: 1, in: sectionID)
                    collectionView.scrollToItem(at: latestMessageIndex, at: .bottom, animated: true)
                } else {
                    // Conversations have the latest message at the first index.
                    collectionView.scrollToItem(at: latestMessageIndex,
                                                at: .centeredHorizontally,
                                                animated: true)
                }
            }
        }
    }

    /// Updates the datasource with the passed in array of conversation changes.
    func update(with changes: [ListChange<Conversation>],
                conversationController: ConversationListController,
                collectionView: UICollectionView) async {


        var snapshot = self.snapshot()

        let sectionID = ConversationSection(sectionID: "channelList",
                                            conversationsController: conversationController)

        // If there's more than one change, reload all of the data.
        guard changes.count == 1 else {
            snapshot.deleteItems(snapshot.itemIdentifiers(inSection: sectionID))
            snapshot.appendItems(conversationController.conversations.asConversationCollectionItems,
                                 toSection: sectionID)
            if !conversationController.hasLoadedAllPreviousChannels {
                snapshot.appendItems([.loadMore], toSection: sectionID)
            }
            await self.apply(snapshot)
            return
        }

        // If this gets set to true, we should scroll to the most recent message after applying the snapshot
        var scrollToLatestMessage = false

        for change in changes {
            switch change {
            case .insert(let conversation, let index):
                snapshot.insertItems([.messages(conversation.id)],
                                     in: sectionID,
                                     atIndex: index.item)
                if conversation.isFromCurrentUser {
                    scrollToLatestMessage = true
                }
            case .move:
                snapshot.deleteItems(snapshot.itemIdentifiers(inSection: sectionID))
                snapshot.appendItems(conversationController.conversations.asConversationCollectionItems,
                                     toSection: sectionID)
            case .update(let message, _):
                snapshot.reconfigureItems([message.asConversationCollectionItem])
            case .remove(let message, _):
                snapshot.deleteItems([message.asConversationCollectionItem])
            }
        }

        // Only show the load more cell if there are previous messages to load.
        snapshot.deleteItems([.loadMore])
        if !conversationController.hasLoadedAllPreviousChannels {
            snapshot.appendItems([.loadMore], toSection: sectionID)
        }

        await Task.onMainActorAsync { [snapshot = snapshot, scrollToLatestMessage = scrollToLatestMessage] in
            self.apply(snapshot)

            // Scroll to the latest message if needed and reconfigure cells as needed.
            if scrollToLatestMessage, let sectionIndex = snapshot.indexOfSection(sectionID) {
                let latestMessageIndex = IndexPath(item: 0, section: sectionIndex)
                if sectionID.isThread {
                    // Inserting a message can cause the visual state of the previous message to change.
                    self.reconfigureItem(atIndex: 1, in: sectionID)
                    collectionView.scrollToItem(at: latestMessageIndex, at: .bottom, animated: true)
                } else {
                    // Conversations have the latest message at the first index.
                    collectionView.scrollToItem(at: latestMessageIndex,
                                                at: .centeredHorizontally,
                                                animated: true)
                }
            }
        }
    }
}

extension LazyCachedMapCollection where Element == Message {

    /// Convenience function to convert Stream chat messages into the ItemType of a ConversationCollectionViewDataSource.
    var asConversationCollectionItems: [ConversationItem] {
        return self.map { message in
            return message.asConversationCollectionItem
        }
    }
}

extension ChatMessage {

    /// Convenience function to convert Stream chat messages into the ItemType of a ConversationCollectionViewDataSource.
    var asConversationCollectionItem: ConversationItem {
        return ConversationItem.messages(self.id)
    }
}

extension Array where Element == Conversation {
    
    var asConversationCollectionItems: [ConversationItem] {
        return self.map { conversation in
            return conversation.asConversationCollectionItem
        }
    }
}

extension Conversation {

    var asConversationCollectionItem: ConversationItem {
        return ConversationItem.messages(self.cid.description)
    }
}
