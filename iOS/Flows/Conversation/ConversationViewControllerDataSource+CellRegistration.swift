//
//  MessageCellRegistration.swift
//  Jibber
//
//  Created by Martin Young on 9/22/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat

extension ConversationCollectionViewDataSource {

    typealias MessageCellRegistration
    = UICollectionView.CellRegistration<MessageSubcell,
                                        (channelID: ChannelId,
                                         messageID: MessageId,
                                         dataSource: ConversationCollectionViewDataSource)>

    typealias ConversationCellRegistration
    = UICollectionView.CellRegistration<ConversationMessagesCell,
                                        (channelID: ChannelId,
                                         dataSource: ConversationCollectionViewDataSource)>
    
    typealias LoadMoreMessagesCellRegistration
    = UICollectionView.CellRegistration<LoadMoreMessagesCell, String>

    static func createMessageCellRegistration() -> MessageCellRegistration {
        return MessageCellRegistration { cell, indexPath, item in
            let messageController = ChatClient.shared.messageController(cid: item.channelID,
                                                                        messageId: item.messageID)
            guard let message = messageController.message else { return }
            cell.configure(with: message, showAuthor: true)
        }
    }

    static func createConversationCellRegistration() -> ConversationCellRegistration {
        return ConversationCellRegistration { cell, indexPath, item in
            let conversationController = ChatClient.shared.channelController(for: item.channelID)
            cell.set(sequence: conversationController.conversation)
        }
    }

    static func createLoadMoreCellRegistration() -> LoadMoreMessagesCellRegistration {
        return LoadMoreMessagesCellRegistration { cell, indexPath, itemIdentifier in
            
        }
    }
}
