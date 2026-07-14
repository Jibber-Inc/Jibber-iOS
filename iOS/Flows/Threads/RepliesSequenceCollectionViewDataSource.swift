//
//  RepliesSequenceCollectionViewDataSource.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/23/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class RepliesSequenceCollectionViewDataSource: MessageSequenceCollectionViewDataSource {

    override var shouldShowReplies: Bool {
        return false
    }
    
    override func set(messagesController: MessageSequenceController,
                      itemsToReconfigure: [MessageSequenceCollectionViewDataSource.ItemType] = [],
                      showLoadMore: Bool = false,
                      completion: (() -> Void)? = nil) {

        self.messageSequenceController = messagesController

        let allMessages = messagesController.messageArray.filter { message in
            return !message.isDeleted
        }

        // The newest message is at the bottom, so reverse the order.
        var allMessageItems = allMessages.map { message in
            return ItemType.message(messageId: message.id)
        }

        if self.shouldPrepareToSend {
            allMessageItems.append(.placeholder)
        }

        if showLoadMore {
            allMessageItems.insert(.loadMore, at: 1)
        }

        var snapshot = self.snapshot()

        var animateDifference = true
        if snapshot.numberOfItems == 0 {
            animateDifference = false
        }

        self.reconcile(allMessageItems, in: &snapshot)

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
}
