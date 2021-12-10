//
//  ConversationListViewController+Extensions.swift
//  Jibber
//
//  Created by Martin Young on 11/12/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat

extension ConversationListViewController {

    func setupInputHandlers() {
        self.collectionView.onDoubleTap { [unowned self] (doubleTap) in
            if self.messageInputAccessoryView.textView.isFirstResponder {
                self.messageInputAccessoryView.textView.resignFirstResponder()
            }
        }

        self.dataSource.handleSelectedMessage = { [unowned self] (item, view) in
            switch item {
            case .message(cid: let channelID, messageID: let messageID):
                self.selectedMessageView = view
                self.onSelectedMessage?(channelID, messageID)
            case .loadMore:
                break
            }
        }

        self.dataSource.handleEditMessage = { item in
            // TODO
        }

        self.dataSource.handleLoadMoreMessages = { [unowned self] in
            self.loadMoreConversationsIfNeeded()
        }
    }

    func subscribeToKeyboardUpdates() {
        KeyboardManager.shared.$willKeyboardShow
            .filter({ willShow in
                if let view = KeyboardManager.shared.inputAccessoryView as? SwipeableInputAccessoryView {
                    return view.textView.restorationIdentifier == self.messageInputAccessoryView.textView.restorationIdentifier
                }
                return false 
            })
            .mainSink { [unowned self] willShow in
                self.state = willShow ? .write : .read
            }.store(in: &self.cancellables)

        KeyboardManager.shared.$cachedKeyboardEndFrame.mainSink { [unowned self] frame in
            self.view.layoutNow()
        }.store(in: &self.cancellables)
    }

    func subscribeToUpdates() {
        self.$state
            .removeDuplicates()
            .mainSink { [unowned self] state in
                self.updateUI(for: state)
            }.store(in: &self.cancellables)

        self.conversationListController
            .channelsChangesPublisher
            .mainSink { [unowned self] changes in
                let nonUpdateChanges = changes.filter { change in
                    switch change {
                    case .update(_, _):
                        return false
                    default:
                        return true
                    }
                }
                Task {
                    await self.dataSource.update(with: nonUpdateChanges,
                                                 conversationController: self.conversationListController,
                                                 collectionView: self.collectionView)
                }.add(to: self.taskPool)
        }.store(in: &self.cancellables)

        self.messageInputAccessoryView.textView.$inputText.mainSink { [unowned self] text in
            guard let cid = self.getCurrentMessageSequence()?.streamCID else { return }
            let conversationController = ChatClient.shared.channelController(for: cid)

            guard conversationController.areTypingEventsEnabled else { return }

            if text.isEmpty {
                conversationController.sendStopTypingEvent()
            } else {
                conversationController.sendKeystrokeEvent()
            }
        }.store(in: &self.cancellables)
    }
}
