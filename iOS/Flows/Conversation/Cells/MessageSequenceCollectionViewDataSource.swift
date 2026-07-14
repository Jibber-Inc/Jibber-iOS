//
//  ConversationMessageCellDatasource.swift
//  Jibber
//
//  Created by Martin Young on 11/3/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

typealias MessageSequenceSection = MessageSequenceCollectionViewDataSource.SectionType
typealias MessageSequenceItem = MessageSequenceCollectionViewDataSource.ItemType

class MessageSequenceCollectionViewDataSource: CollectionViewDataSource<MessageSequenceSection,
                                               MessageSequenceItem> {

    enum SectionType: Int, Hashable, CaseIterable {
        case messages
    }

    enum ItemType: Hashable {
        case message(messageId: String,
                     showDetail: Bool = true)
        case loadMore
        case placeholder
        case initial
    }

    /// A conversation controller created for this message sequence.
    ///
    /// Keep presentation metadata indexed here so the collection view layout and
    /// cell provider never have to scan the full message array for an identifier.
    var messageSequenceController: MessageSequenceController = EmptyMessageSequenceController() {
        didSet {
            self.rebuildMessageIndex()
        }
    }

    private var visibleMessages: [Messageable] = []
    private var messagesByID: [String: Messageable] = [:]
    private var timeMachineItemsByMessageID: [String: TimeMachineLayoutItem] = [:]
    private var userCreatedMessageIDs: Set<String> = []
    private var oldestMessageDate: Date = .distantPast

    // Input handling
    weak var messageContentDelegate: MessageContentDelegate?
    var handleLoadMoreMessages: ((String) -> Void)?
    var handleAddMembers: CompletionOptional = nil

    /// If true, show the replies for each message
    var shouldShowReplies: Bool {
        return true 
    }
    /// If true, show the detail bar for each message
    var shouldShowDetailBar = true
    /// If true, push the bottom messages back to prepare for a new message.
    var shouldPrepareToSend = false
    /// If true, set up the messages to accomodate a drop zone being shown.
    var layoutForDropZone: Bool = false

    // Cell registration
    private let messageCellRegistration
    = MessageSequenceCollectionViewDataSource.createMessageCellRegistration()
    private let loadMoreRegistration
    = MessageSequenceCollectionViewDataSource.createLoadMoreCellRegistration()
    private let placeholderRegistration
    = MessageSequenceCollectionViewDataSource.createPlaceholderMessageCellRegistration()
    private let initialCellRegistration
    = MessageSequenceCollectionViewDataSource.createInitialCellRegistration()
    
    override func dequeueCell(with collectionView: UICollectionView,
                              indexPath: IndexPath,
                              section: SectionType,
                              item: ItemType) -> UICollectionViewCell? {

        switch item {
        case .message(messageId: let messageId, let showDetail):
            guard let message = self.messagesByID[messageId] else {
                logDebug("WARNING: Message not found in the data source index.")
                return nil
            }

            let messageCell
            = collectionView.dequeueConfiguredReusableCell(using: self.messageCellRegistration,
                                                           for: indexPath,
                                                           item: (message,
                                                                  showDetail))

            messageCell.shouldShowReplies = self.shouldShowReplies
            messageCell.shouldShowDetailBar = self.shouldShowDetailBar
            messageCell.content.delegate = self.messageContentDelegate

            return messageCell
        case .loadMore:
            let loadMoreCell = collectionView.dequeueConfiguredReusableCell(using: self.loadMoreRegistration,
                                                                            for: indexPath,
                                                                            item: collectionView)
            if let conversationId = self.messageSequenceController.conversationId {
                loadMoreCell.handleLoadMoreMessages = { [unowned self] in
                    self.handleLoadMoreMessages?(conversationId)
                }
            }
            return loadMoreCell
        case .placeholder:
            return collectionView.dequeueConfiguredReusableCell(using: self.placeholderRegistration,
                                                                for: indexPath,
                                                                item: collectionView)
        case .initial:
            let cell = collectionView.dequeueConfiguredReusableCell(using: self.initialCellRegistration,
                                                                    for: indexPath,
                                                                    item: (self.messageSequenceController,
                                                                           collectionView))
            cell.didTapAddMembers = { [unowned self] in
                self.handleAddMembers?()
            }
            return cell
        }
    }

    /// Updates the datasource to display the given message sequence.
    /// The message sequence should be ordered newest to oldest.
    func set(messagesController: MessageSequenceController,
             itemsToReconfigure: [ItemType] = [],
             showLoadMore: Bool = false,
             completion: (() -> Void)? = nil
    ) {
        self.updateSnapshot(
            messagesController: messagesController,
            itemsToReconfigure: itemsToReconfigure,
            showLoadMore: showLoadMore,
            completion: completion
        )
    }

    private func updateSnapshot(
        messagesController: MessageSequenceController,
        itemsToReconfigure: [ItemType],
        showLoadMore: Bool,
        completion: (() -> Void)?
    ) {

        self.messageSequenceController = messagesController

        // The newest message is at the bottom, so reverse the order.
        var messageItems = self.visibleMessages.map { message in
            return ItemType.message(messageId: message.id)
        }
        messageItems = messageItems.reversed()

        if self.shouldPrepareToSend {
            messageItems.append(.placeholder)
        }

        if showLoadMore {
            messageItems.insert(.loadMore, at: 0)
        } else {
           // messageItems.insert(.initial, at: 0)
        }
        
        var snapshot = self.snapshot()

        var animateDifference = true
        if snapshot.numberOfItems == 0 {
            animateDifference = false
        }

        self.reconcile(messageItems, in: &snapshot)

        let existingItemsToReconfigure = itemsToReconfigure.filter {
            snapshot.indexOfItem($0) != nil
        }
        snapshot.reconfigureItems(existingItemsToReconfigure)

        if let completion {
            self.apply(
                snapshot,
                animatingDifferences: animateDifference,
                completion: completion
            )
        } else {
            self.apply(snapshot, animatingDifferences: animateDifference)
        }
    }

    func setAndWait(
        messagesController: MessageSequenceController,
        itemsToReconfigure: [ItemType] = [],
        showLoadMore: Bool = false
    ) async {
        await withCheckedContinuation { continuation in
            self.set(
                messagesController: messagesController,
                itemsToReconfigure: itemsToReconfigure,
                showLoadMore: showLoadMore
            ) {
                continuation.resume()
            }
        }
    }

    /// Reconciles the message section while preserving stable item identifiers.
    /// Diffable data source can then animate just the inserts, deletes, and moves
    /// instead of treating every message update as a brand-new section.
    func reconcile(_ desiredItems: [ItemType], in snapshot: inout SnapshotType) {
        if !snapshot.sectionIdentifiers.contains(.messages) {
            snapshot.appendSections([.messages])
        }

        let desiredItemSet = Set(desiredItems)
        let removedItems = snapshot.itemIdentifiers(inSection: .messages).filter {
            !desiredItemSet.contains($0)
        }
        snapshot.deleteItems(removedItems)

        var currentItems = snapshot.itemIdentifiers(inSection: .messages)
        guard currentItems != desiredItems else { return }

        if currentItems.isEmpty {
            snapshot.appendItems(desiredItems, toSection: .messages)
            return
        }

        var currentItemSet = Set(currentItems)

        for (index, item) in desiredItems.enumerated() where !currentItemSet.contains(item) {
            let followingItem = desiredItems.dropFirst(index + 1).first {
                currentItemSet.contains($0)
            }

            if let followingItem,
               let followingIndex = currentItems.firstIndex(of: followingItem) {
                snapshot.insertItems([item], beforeItem: followingItem)
                currentItems.insert(item, at: followingIndex)
            } else {
                snapshot.appendItems([item], toSection: .messages)
                currentItems.append(item)
            }
            currentItemSet.insert(item)
        }

        for (desiredIndex, desiredItem) in desiredItems.enumerated() {
            guard currentItems[safe: desiredIndex] != desiredItem,
                  let currentIndex = currentItems.firstIndex(of: desiredItem),
                  let displacedItem = currentItems[safe: desiredIndex] else {
                continue
            }

            snapshot.moveItem(desiredItem, beforeItem: displacedItem)
            currentItems.remove(at: currentIndex)
            currentItems.insert(desiredItem, at: desiredIndex)
        }
    }

    private func rebuildMessageIndex() {
        let oldMessagesByID = self.messagesByID
        let oldTimeMachineItemsByMessageID = self.timeMachineItemsByMessageID
        let oldUserCreatedMessageIDs = self.userCreatedMessageIDs

        let allMessages = self.messageSequenceController.messageArray
        self.visibleMessages = allMessages.filter { !$0.isDeleted }
        self.messagesByID = [:]
        self.timeMachineItemsByMessageID = [:]
        self.userCreatedMessageIDs = []

        for message in allMessages {
            self.messagesByID[message.id] = message
            self.timeMachineItemsByMessageID[message.id] = TimeMachineLayoutItem(
                date: message.createdAt,
                stableID: message.id
            )
            if message.isFromCurrentUser {
                self.userCreatedMessageIDs.insert(message.id)
            }
        }
        self.oldestMessageDate = allMessages.last?.createdAt ?? .distantPast

        // Diffable updates may briefly ask for an outgoing cell's attributes
        // while animating to the new snapshot. Retain only those old values that
        // are still represented by the currently applied snapshot.
        let appliedMessageIDs = self.snapshot().itemIdentifiers.compactMap { item -> String? in
            guard case .message(let messageID, _) = item else { return nil }
            return messageID
        }
        for messageID in appliedMessageIDs where self.messagesByID[messageID] == nil {
            self.messagesByID[messageID] = oldMessagesByID[messageID]
            self.timeMachineItemsByMessageID[messageID] = oldTimeMachineItemsByMessageID[messageID]
            if oldUserCreatedMessageIDs.contains(messageID) {
                self.userCreatedMessageIDs.insert(messageID)
            }
        }
    }
}

// MARK: - Cell Registration

extension MessageSequenceCollectionViewDataSource {

    typealias MessageCellRegistration
    = UICollectionView.CellRegistration<MessageCell,
                                        (message: Messageable,
                                         showDetail: Bool)>
    typealias LoadMoreCellRegistration
    = UICollectionView.CellRegistration<LoadMoreMessagesCell, UICollectionView?>
    typealias PlaceholderMessageCellRegistration
    = UICollectionView.CellRegistration<PlaceholderMessageCell, UICollectionView?>
    typealias InitialMessageCellRegistration
    = UICollectionView.CellRegistration<InitialMessageCell, (MessageSequenceController, UICollectionView?)>

    static func createMessageCellRegistration() -> MessageCellRegistration {
        return MessageCellRegistration { cell, indexPath, item in
            cell.shouldShowDetailBar = item.showDetail
            cell.configure(with: item.message)
        }
    }

    static func createLoadMoreCellRegistration() -> LoadMoreCellRegistration {
        return LoadMoreCellRegistration { cell, indexPath, item in }
    }

    static func createPlaceholderMessageCellRegistration() -> PlaceholderMessageCellRegistration {
        return PlaceholderMessageCellRegistration { cell, indexPath, itemIdentifier in }
    }
    
    static func createInitialCellRegistration() -> InitialMessageCellRegistration {
        return InitialMessageCellRegistration { cell, indexPath, item in
            cell.configure(with: item.0)
        }
    }
}

// MARK: - TimelineCollectionViewLayoutDataSource

extension MessageSequenceCollectionViewDataSource: MessagesTimeMachineCollectionViewLayoutDataSource {

    func getTimeMachineItem(forItemAt indexPath: IndexPath) -> TimeMachineLayoutItemType {
        guard let item = self.itemIdentifier(for: indexPath) else {
            return TimeMachineLayoutItem(date: Date.distantPast, stableID: nil)
        }

        return self.getTimeMachineItem(forItem: item)
    }

    private func getTimeMachineItem(forItem item: ItemType) -> TimeMachineLayoutItemType {
        switch item {
        case .message(let messageId, _):
            return self.timeMachineItemsByMessageID[messageId]
                ?? TimeMachineLayoutItem(date: .distantPast, stableID: messageId)
        case .loadMore:
            // Get the oldest loaded message and set the date slightly before that.
            return TimeMachineLayoutItem(
                date: self.oldestMessageDate - 0.001,
                stableID: "load-more"
            )
        case .initial:
            return TimeMachineLayoutItem(date: .distantPast, stableID: "initial")
        case .placeholder:
            return TimeMachineLayoutItem(date: .distantFuture, stableID: "placeholder")
        }
    }

    func isUserCreatedItem(at indexPath: IndexPath) -> Bool {
        guard let item = self.itemIdentifier(for: indexPath) else { return false }

        switch item {
        case .message(let messageId, _):
            // We should always scroll to the end when inserting messages from our selves
            return self.userCreatedMessageIDs.contains(messageId)
        case .loadMore, .initial:
            return false
        case .placeholder:
            return true
        }
    }
}

private struct TimeMachineLayoutItem: TimeMachineLayoutItemType {
    var date: Date
    var stableID: String?
}
