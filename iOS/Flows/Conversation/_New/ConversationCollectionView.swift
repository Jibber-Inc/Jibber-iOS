//
//  ConversationCollectionView.swift
//  Jibber
//
//  Created by Martin Young on 10/7/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

/// A collection view for displaying conversation messages.
/// Messages are ordered right to left. So the first message in the data source is on the far right.
/// It automatically creates its own custom layout object.
class ConversationCollectionView: CollectionView {

    let conversationLayout: new_ConversationCollectionViewLayout

    init() {
        self.conversationLayout = new_ConversationCollectionViewLayout()

        super.init(layout: self.conversationLayout)

        self.decelerationRate = .normal
        self.showsHorizontalScrollIndicator = false
        self.semanticContentAttribute = .forceRightToLeft
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
