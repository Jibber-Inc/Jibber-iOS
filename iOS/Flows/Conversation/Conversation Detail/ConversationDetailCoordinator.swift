//
//  ConversationDetailCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/21/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Localization
import Coordinator

enum DetailCoordinatorResult {
    case conversation(String)
    case message(Messageable)
}

class ConversationDetailCoordinator: PresentableCoordinator<DetailCoordinatorResult?> {
    
    lazy var detailVC = ConversationDetailViewController(with: self.conversationId)
    let conversationId: String
    
    init(with conversationId: String,
         router: CoordinatorRouter,
         deepLink: DeepLinkable?) {
        self.conversationId = conversationId
        super.init(router: router, deepLink: deepLink)
    }
    
    override func toPresentable() -> DismissableVC {
        return self.detailVC
    }
    
    override func start() {
        super.start()
        
        self.detailVC.dataSource.messageContentDelegate = self
        
        self.detailVC.$selectedItems.mainSink { [unowned self] items in
            guard let first = items.first else { return }
            
            switch first {
            case .pinnedMessage(let model):
                guard let conversationId = model.conversationId,
                        let messageId = model.messageId,
                        let message = JibberMessagingClient.shared.message(conversationId: conversationId, id: messageId) else { return }
                self.finishFlow(with: .message(message))
            case .member(let member):
                guard let person = PeopleStore.shared.people.first(where: { person in
                    return person.personId == member.personId
                }) else { return }
                
                self.presentProfile(for: person)
            case .info(_):
                break
            case .editTopic(let conversationId):
                self.presentConversationTitleAlert(for: conversationId)
            case .detail(let option):
                if option == .add {
                    self.presentPeoplePicker()
                } else {
                    self.presentDetail(option: option)
                }
            }
        }.store(in: &self.cancellables)
    }
    
    func presentProfile(for person: PersonType) {
        self.removeChild()
        
        let coordinator = ProfileCoordinator(with: person, router: self.router, deepLink: self.deepLink)
        
        self.addChildAndStart(coordinator) { [unowned self] result in
            self.detailVC.dismiss(animated: true) { [unowned self] in
                switch result {
                case .conversation(let cid):
                    self.finishFlow(with: .conversation(cid.description))
                default:
                    break 
                }
            }
        }
        
        self.router.present(coordinator, source: self.detailVC, cancelHandler: nil)
    }
    
    func presentConversationTitleAlert(for conversationId: String) {
        let controller = JibberMessagingClient.shared.conversationController(for: conversationId)
        
        let alertController = UIAlertController(title: "Update Name", message: "", preferredStyle: .alert)
        alertController.addTextField { (textField : UITextField!) -> Void in
            textField.placeholder = "Name"
            textField.autocapitalizationType = .words
        }
        let saveAction = UIAlertAction(title: "Confirm", style: .default, handler: { alert -> Void in
            if let textField = alertController.textFields?.first,
               let text = textField.text,
               !text.isEmpty {
                
                controller?.updateChannel(name: text, imageURL: nil, team: nil) { _ in
                    alertController.dismiss(animated: true, completion: {
                        Task {
                            await ToastScheduler.shared.schedule(toastType: .success(ImageSymbol.thumbsUp, "Name updated"))
                        }
                    })
                }
            }
        })
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alertController.addAction(saveAction)
        alertController.addAction(cancelAction)
        
        self.detailVC.present(alertController, animated: true, completion: nil)
    }
    
    func presentDetail(option: ConversationDetailCollectionViewDataSource.OptionType) {
        guard let controller = JibberMessagingClient.shared.conversationController(for: self.conversationId) else { return }
        
        var title: String = ""
        var message: String = ""
        var style: UIAlertAction.Style = .default
        
        switch option {
        case .hide:
            title = "Hide"
            message = "Hiding this conversation will archive the conversation until a new message is sent to it."
        case .leave:
            title = "Leave"
            message = "Leaving the conversation will remove you as a participant."
        case .delete:
            title = "Delete"
            message = "Deleting a conversation will remove all members and data associated with this conversation."
            style = .destructive
        case .add:
            return
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        
        let primaryAction = UIAlertAction(title: title, style: style, handler: {
            (action : UIAlertAction!) -> Void in
            Task {
                switch option {
                case .hide:
                    try? await controller.hideChannel(clearHistory: false)
                    Task.onMainActor {
                        self.finishFlow(with: nil)
                    }
                case .leave:
                    let user = User.current()!.objectId!
                    try? await controller.removeMembers(userIds: Set.init([user]))
                    Task.onMainActor {
                        self.finishFlow(with: nil)
                    }
                case .delete:
                    try? await controller.deleteChannel()
                    Task.onMainActor {
                        self.finishFlow(with: nil)
                    }
                case .add:
                    return
                }
            }.add(to: self.taskPool)
        })
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alertController.addAction(primaryAction)
        alertController.addAction(cancelAction)
        
        self.detailVC.present(alertController, animated: true, completion: nil)
    }
    
    func presentPeoplePicker() {
        guard let conversation = JibberMessagingClient.shared.conversation(for: self.conversationId) else { return }
        
        self.removeChild()
        
        let coordinator = PeopleCoordinator(router: self.router, deepLink: self.deepLink)
        coordinator.selectedConversationId = self.conversationId
        
        // Because of how the People are presented, we need to properly reset the KeyboardManager.
        coordinator.toPresentable().dismissHandlers.append { [unowned self, unowned cor = coordinator] in
            let invitedPeople = cor.invitedPeople
            self.handleInviteFlowEnded(givenInvitedPeople: invitedPeople, activeConversation: conversation)
        }
        
        self.addChildAndStart(coordinator) { [unowned self] result in
            self.detailVC.dismiss(animated: true, completion: nil)
        }
        
        self.router.present(coordinator, source: self.detailVC)
    }
    
    private func handleInviteFlowEnded(givenInvitedPeople invitedPeople: [Person],
                                       activeConversation: Conversation) {
        
        if !invitedPeople.isEmpty {
            Task {
                guard let controller = JibberMessagingClient.shared.conversationController(for: activeConversation.id) else { return }
                await self.add(people: invitedPeople, to: controller)
                try? await controller.synchronize()
                await self.detailVC.reloadPeople()
            }
        }
    }
    
    func add(people: [Person], to controller: ConversationController) async {
        return await withCheckedContinuation { continuation in
            let acceptedConnections = people.compactMap { person in
                return person.connection
            }.filter { connection in
                return connection.status == .accepted
            }
            
            guard !acceptedConnections.isEmpty else {
                continuation.resume(returning: ())
                return
            }
            
            let members = acceptedConnections.compactMap { connection in
                return connection.nonMeUser?.objectId
            }
            controller.addMembers(userIds: Set(members)) { _ in
                self.showPeopleAddedToast(for: acceptedConnections)
                continuation.resume(returning: ())
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
}

extension ConversationDetailCoordinator: MessageContentDelegate {
    
    func messageContent(_ content: MessageContentView, didTapMessage message: Messageable) {
        self.finishFlow(with: .message(message))
    }
    
    func messageContent(_ content: MessageContentView, didTapAttachmentForMessage message: Messageable) {
        
        switch message.kind {
        case .photo(photo: let photo, _):
            self.presentMediaFlow(for: [photo], startingItem: nil, message: message)
        case .video(video: let video, _):
            self.presentMediaFlow(for: [video], startingItem: nil, message: message)
        case .media(items: let media, _):
            self.presentMediaFlow(for: media, startingItem: nil, message: message)
        case .text, .attributedText, .location, .emoji, .audio, .contact, .link:
            break
        }
    }
    
    func presentMediaFlow(for mediaItems: [MediaItem],
                          startingItem: MediaItem?,
                          message: Messageable) {
        self.removeChild()
        let coordinator = MediaCoordinator(items: mediaItems,
                                           startingItem: startingItem,
                                           message: message,
                                           router: self.router,
                                           deepLink: self.deepLink)
        self.addChildAndStart(coordinator) { _ in }
        self.router.present(coordinator, source: self.detailVC, cancelHandler: nil)
    }
}
