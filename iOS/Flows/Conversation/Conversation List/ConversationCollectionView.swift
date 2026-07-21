//
//  ConversationCollectionView.swift
//  Jibber
//
//  Created by Martin Young on 1/10/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

/// Production adapter for the shared Time Machine rail.
class ConversationCollectionView: ConversationTimeMachineCollectionView {

    var conversationLayout: MessagesTimeMachineCollectionViewLayout {
        return self.collectionViewLayout as! MessagesTimeMachineCollectionViewLayout
    }

    init() {
        let itemHeight = MessageContentView.bubbleHeight
            + MessageFooterView.height
            + Theme.ContentOffset.standard.value
        super.init(layout: MessagesTimeMachineCollectionViewLayout(itemHeight: itemHeight))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ConversationCollectionView: MessageSendingCollectionViewType {

    /// Returns the frame that a message drop zone should have, based on this cell's contents.
    /// The frame is in the coordinate space of the passed in view.
    func getMessageDropZoneFrame(convertedTo targetView: UIView) -> CGRect {
        let dropZoneFrame = self.conversationLayout.getDropZoneFrame()

        return self.convert(dropZoneFrame, to: targetView)
    }

    func getNewConversationContentOffset() -> CGPoint {
        return .zero
    }
}
