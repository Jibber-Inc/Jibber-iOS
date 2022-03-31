//
//  CircleCollectionViewDataSource.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/26/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation


typealias RoomSectionType = RoomCollectionViewDataSource.SectionType
typealias RoomItemType = RoomCollectionViewDataSource.ItemType

class RoomCollectionViewDataSource: CollectionViewDataSource<RoomSectionType, RoomItemType> {

    enum SectionType: Int, CaseIterable {
        case members
        case conversations
    }

    enum ItemType: Hashable {
        case memberId(String)
        case conversation(ConversationId)
    }

    private let config = ManageableCellRegistration<RoomMemberCell>().provider
    private let conversationConfig = ManageableCellRegistration<ConversationCell>().provider

    // MARK: - Cell Dequeueing

    override func dequeueCell(with collectionView: UICollectionView,
                              indexPath: IndexPath,
                              section: SectionType,
                              item: ItemType) -> UICollectionViewCell? {
        switch item {
        case .memberId(let member):
            return collectionView.dequeueConfiguredReusableCell(using: self.config,
                                                                for: indexPath,
                                                                item: member)
        case .conversation(let cid):
            return collectionView.dequeueConfiguredReusableCell(using: self.conversationConfig,
                                                                for: indexPath,
                                                                item: cid)
        }
    }
}
