//
//  MessageTimeMachineCollectionViewLayout.swift
//  Jibber
//
//  Created by Martin Young on 12/3/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import UIKit

protocol MessagesTimeMachineCollectionViewLayoutDataSource: TimeMachineCollectionViewLayoutDataSource {
    /// Return true if the item at the given index path was created by the current user.
    func isUserCreatedItem(at indexPath: IndexPath) -> Bool
}

/// Production specialization of the shared message Time Machine. The shared
/// superclass owns all geometry and presentation interpolation; this adapter
/// only preserves production's new-message auto-follow behavior.
class MessagesTimeMachineCollectionViewLayout: ConversationTimeMachineCollectionViewLayout {

    /// Compatibility initializer for production call sites. Shared/App Clip
    /// consumers initialize the superclass with their own content height.
    convenience init() {
        self.init(
            itemHeight: MessageContentView.bubbleHeight
                + MessageFooterView.height
                + Theme.ContentOffset.standard.value
        )
    }

    /// Setting this also sets the super class datasource variable.
    weak var messageDataSource: MessagesTimeMachineCollectionViewLayoutDataSource? {
        get { return self.dataSource as? MessagesTimeMachineCollectionViewLayoutDataSource }
        set { self.dataSource = newValue }
    }
    
    // MARK: - Attribute Helpers

    func getDropZoneFrame() -> CGRect {
        let center = self.getItemCenterPoint(withYOffset: 0, scale: 1)
        var frame = CGRect(x: 0,
                           y: 0,
                           width: self.collectionView!.width,
                           height: self.itemHeight)
        frame.center = center
        // Shift the drop zone up a bit to account for the invisible space under the cell.
        frame.top -= 60
        
        return frame
    }

    private func getMostRecentItemContentOffset() -> CGPoint? {
        return CGPoint(x: 0, y: self.maxZPosition)
    }

    // MARK: - Content Offset and Update Animation Handling

    /// If true, scroll to the most recent item after performing collection view updates.
    private var shouldScrollToEnd = false

    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)

        guard let collectionView = self.collectionView,
              let mostRecentOffset = self.getMostRecentItemContentOffset() else { return }

        for update in updateItems {
            switch update.updateAction {
            case .insert:
                guard let indexPath = update.indexPathAfterUpdate else { break }

                let isUserCreatedItem: Bool
                if let messageDataSource = self.messageDataSource {
                    isUserCreatedItem = messageDataSource.isUserCreatedItem(at: indexPath)
                } else {
                    isUserCreatedItem = false
                    logDebug("WARNING: No delegate is assigned to MessageLayout.")
                }

                let isInsertedAtFront = indexPath.item == self.numberOfItems(inSection: 0) - 1

                let isScrolledToFront
                = (mostRecentOffset.y - collectionView.contentOffset.y) <= self.itemHeight

                // When a new message comes and we're at the front, always currently scrolled to the
                // new message.
                if (isUserCreatedItem && isInsertedAtFront) || isScrolledToFront {
                    self.shouldScrollToEnd = true
                    break
                }


            case .delete, .reload, .move, .none:
                break
            @unknown default:
                break
            }
        }
    }

    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()

        self.shouldScrollToEnd = false
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        if self.shouldScrollToEnd, let mostRecentOffset = self.getMostRecentItemContentOffset() {
            return mostRecentOffset
        }

        return super.targetContentOffset(forProposedContentOffset: proposedContentOffset)
    }
}
