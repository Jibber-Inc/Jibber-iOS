//
//  ConversationViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 12/27/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Parse
import Combine
import StreamChat

class ConversationThreadViewController: DiffableCollectionViewController<ConversationCollectionSection,
                                        ConversationCollectionItem,
                                        ConversationCollectionViewDataSource>,
                                        CollectionViewInputHandler {

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))

    let messageController: ChatMessageController
    var message: Message! {
        return self.messageController.message
    }

    private(set) var conversationController: ChatChannelController?

    var collectionViewBottomInset: CGFloat = 0 {
        didSet {
            self.collectionView.contentInset.bottom = self.collectionViewBottomInset
            self.collectionView.verticalScrollIndicatorInsets.bottom = self.collectionViewBottomInset
        }
    }

    var indexPathForEditing: IndexPath?

    var inputTextView: InputTextView {
        return self.messageInputAccessoryView.textView
    }

    // Custom Input Accessory View
    lazy var messageInputAccessoryView = ConversationInputAccessoryView(with: self)

    override var inputAccessoryView: UIView? {
        return self.messageInputAccessoryView
    }

    override var canBecomeFirstResponder: Bool {
        return true 
    }

    init(channelID: ChannelId, messageID: MessageId) {
        self.messageController = ChatClient.shared.messageController(cid: channelID, messageId: messageID)
        self.messageController.listOrdering = .bottomToTop
        self.conversationController = ChatClient.shared.channelController(for: channelID,
                                                                             messageOrdering: .topToBottom)
        super.init(with: ConversationThreadCollectionView())
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        self.dataSource.messageStyle = .thread

        self.view.insertSubview(self.blurView, belowSubview: self.collectionView)

        self.subscribeToUpdates()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.resignFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.blurView.expandToSuperviewSize()
    }

    // MARK: Data Loading

    override func getAllSections() -> [ConversationCollectionSection] {
        if let channelId = self.message.cid {
           return [.conversation(channelId)]
        }

        return []
    }

    override func retrieveDataForSnapshot() async -> [ConversationCollectionSection : [ConversationCollectionItem]] {
        var data: [ConversationCollectionSection: [ConversationCollectionItem]] = [:]

        do {
            try await self.messageController.loadPreviousReplies()
            let messages = Array(self.messageController.replies.asConversationCollectionItems)

            if let channelId = self.message.cid {
                data[.conversation(channelId)] = messages
            }
        } catch {
            logDebug(error)
        }
        
        return data
    }
}
