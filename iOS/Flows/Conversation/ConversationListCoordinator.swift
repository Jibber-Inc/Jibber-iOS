//
//  ConversationCoordinator.swift
//  Benji
//
//  Created by Benji Dodgson on 8/14/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Photos
import PhotosUI
import Combine
import StreamChat
import Localization

class ConversationListCoordinator: PresentableCoordinator<Void>, ActiveConversationable {

    lazy var conversationListVC
    = ConversationListViewController(members: self.conversationMembers,
                                     startingConversationID: self.startingConversationID,
                                     startingMessageID: self.startMessageID)

    private let conversationMembers: [ConversationMember]
    private let startingConversationID: ConversationId?
    private let startMessageID: MessageId?

    override func toPresentable() -> DismissableVC {
        return self.conversationListVC
    }

    init(router: Router,
         deepLink: DeepLinkable?,
         conversationMembers: [ConversationMember],
         startingConversationId: ConversationId?,
         startingMessageId: MessageId?) {

        self.conversationMembers = conversationMembers
        self.startingConversationID = startingConversationId
        self.startMessageID = startingMessageId

        super.init(router: router, deepLink: deepLink)
    }

    override func start() {
        super.start()

        self.conversationListVC.onSelectedMessage = { [unowned self] (channelId, messageId, replyId) in
            self.presentThread(for: channelId,
                                  messageId: messageId,
                                  startingReplyId: replyId)
        }

        self.conversationListVC.headerVC.didTapAddPeople = { [unowned self] in
            self.presentPeoplePicker()
        }
        
        self.conversationListVC.swipeInputDelegate.didTapAvatar = { [unowned self] in
            self.presentProfilePicture()
        }

        self.conversationListVC.headerVC.didTapUpdateTopic = { [unowned self] in
            guard let conversation = self.activeConversation else {
                logDebug("Unable to change topic because no conversation is selected.")
                return
            }
            guard conversation.isOwnedByMe else {
                logDebug("Unable to change topic because conversation is not owned by user.")
                return
            }
            self.presentConversationTitleAlert(for: conversation)
        }
        
        self.conversationListVC.dataSource.handleCreateGroupSelected = { [unowned self] in
            self.presentCircle()
        }

        Task {
            await self.checkForPermissions()
        }
    }

    func handle(deeplink: DeepLinkable) {
        self.deepLink = deeplink

        guard let target = deeplink.deepLinkTarget else { return }

        switch target {
        case .conversation:
            let messageID = deeplink.messageId
            guard let cid = deeplink.conversationId else { break }
            Task {
                await self.conversationListVC.scrollToConversation(with: cid, messageID: messageID)
            }.add(to: self.taskPool)

        default:
            break
        }
    }
    
    func presentCircle() {
        self.removeChild()
        let coordinator = CircleCoordinator(router: self.router, deepLink: self.deepLink)
        self.addChildAndStart(coordinator) { [unowned self] _ in
            self.router.dismiss(source: self.conversationListVC)
        }

        self.conversationListVC.updateUI(for: .read)
        self.router.present(coordinator, source: self.conversationListVC)
    }

    func presentThread(for channelId: ChannelId,
                       messageId: MessageId,
                       startingReplyId: MessageId?) {

        self.removeChild()
        
        let coordinator = ThreadCoordinator(with: channelId,
                                            messageId: messageId,
                                            startingReplyId: startingReplyId,
                                            router: self.router,
                                            deepLink: self.deepLink)

        self.addChildAndStart(coordinator) { [unowned self] _ in
            self.router.dismiss(source: self.conversationListVC)
        }

        self.conversationListVC.updateUI(for: .read)
        self.router.present(coordinator, source: self.conversationListVC)
    }
    
    func presentProfilePicture() {
        let vc = ModalPhotoViewController()
        
        // Because of how the People are presented, we need to properly reset the KeyboardManager.
        vc.dismissHandlers.append { [unowned self] in
            self.conversationListVC.becomeFirstResponder()
        }
        
        vc.onDidComplete = { _ in
            vc.dismiss(animated: true, completion: nil)
        }

        self.conversationListVC.resignFirstResponder()
        self.router.present(vc, source: self.conversationListVC)
    }

    func presentPeoplePicker() {
        guard let conversation = self.activeConversation else { return }

        self.removeChild()
        let coordinator = PeopleCoordinator(conversationID: conversation.cid,
                                            router: self.router,
                                            deepLink: self.deepLink)
        
        // Because of how the People are presented, we need to properly reset the KeyboardManager.
        coordinator.toPresentable().dismissHandlers.append { [unowned self] in
            self.conversationListVC.becomeFirstResponder()
        }

        self.addChildAndStart(coordinator) { [unowned self] connections in
            self.router.dismiss(source: coordinator.toPresentable(), animated: true) { [unowned self] in
                self.conversationListVC.becomeFirstResponder()
                self.add(connections: connections, to: conversation)
            }
        }

        self.conversationListVC.resignFirstResponder()
        self.router.present(coordinator, source: self.conversationListVC)
    }

    func add(connections: [Connection], to conversation: Conversation) {
        let controller = ChatClient.shared.channelController(for: conversation.cid)

        let acceptedConnections = connections.filter { connection in
            return connection.status == .accepted
        }

        if !acceptedConnections.isEmpty {
            let members = acceptedConnections.compactMap { connection in
                return connection.nonMeUser?.objectId
            }
            controller.addMembers(userIds: Set(members)) { error in
                if error.isNil {
                    self.showPeopleAddedToast(for: acceptedConnections)
                }
            }
        }
    }

    private func showPeopleAddedToast(for connections: [Connection]) {
        Task {
            if connections.count == 1, let first = connections.first?.nonMeUser {
                let text = LocalizedString(id: "", arguments: [first.fullName], default: "@(name) has been added to the conversation.")
                await ToastScheduler.shared.schedule(toastType: .basic(identifier: Lorem.randomString(), displayable: first, title: "\(first.givenName.capitalized) Added", description: text, deepLink: nil))
            } else {
                let text = LocalizedString(id: "", arguments: [String(connections.count)], default: " @(count) people have been added to the conversation.")
                await ToastScheduler.shared.schedule(toastType: .basic(identifier: Lorem.randomString(), displayable: User.current()!, title: "\(String(connections.count)) Added", description: text, deepLink: nil))
            }
        }.add(to: self.taskPool)
    }

    func presentConversationTitleAlert(for conversation: Conversation) {
        let controller = ChatClient.shared.channelController(for: conversation.cid)

        let alertController = UIAlertController(title: "Update Topic", message: "", preferredStyle: .alert)
        alertController.addTextField { (textField : UITextField!) -> Void in
            textField.placeholder = "Topic"
        }
        let saveAction = UIAlertAction(title: "Confirm", style: .default, handler: { [unowned self] alert -> Void in
            if let textField = alertController.textFields?.first,
               let text = textField.text,
               !text.isEmpty {

                controller.updateChannel(name: text, imageURL: nil, team: nil) { [unowned self] error in
                    self.conversationListVC.headerVC.topicLabel.setText(text)
                    self.conversationListVC.headerVC.view.layoutNow()
                    alertController.dismiss(animated: true, completion: {
                        self.conversationListVC.becomeFirstResponder()
                    })
                }
            }
        })

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: {
            (action : UIAlertAction!) -> Void in
            self.conversationListVC.becomeFirstResponder()
        })

        alertController.addAction(saveAction)
        alertController.addAction(cancelAction)
        
        self.conversationListVC.resignFirstResponder()

        self.conversationListVC.present(alertController, animated: true, completion: nil)
    }
}
