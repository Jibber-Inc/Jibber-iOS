//
//  ConversationCoordinator+Presentation.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/26/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import Localization
import ParseCore
import Photos

extension ConversationCoordinator {
    
    func presentPersonConnection(for activity: LaunchActivity) {
        let coordinator = PersonConnectionCoordinator(launchActivity: activity,
                                                      router: self.router,
                                                      deepLink: self.deepLink)

        self.present(coordinator)
    }
    
    func presentMessageDetail(for message: Messageable) {
        let coordinator = MessageDetailCoordinator(with: message,
                                                   router: self.router,
                                                   deepLink: self.deepLink)
        
        self.present(coordinator) { [unowned self] result in
            switch result {
            case .message(_):
                self.presentThread(for: message, startingReplyId: nil)
            case .reply(let replyId):
                self.presentThread(for: message, startingReplyId: replyId)
            case .conversation(let conversationId):
                Task.onMainActorAsync {
                    await self.conversationVC.scrollToConversation(with: conversationId,
                                                                   messageId: nil,
                                                                   animateScroll: false)
                }
            case .none:
                break
            }
        }
    }
    
    func presentPeoplePicker() {
        // If there is no conversation to invite people to, then do nothing.
        guard let conversation = self.activeConversation else { return }
        
        let coordinator = PeopleCoordinator(router: self.router, deepLink: self.deepLink)
        coordinator.selectedConversationId = self.activeConversation?.id
        
        self.present(coordinator, finishedHandler: { [unowned self] invitedPeople in
            self.handleInviteFlowEnded(givenInvitedPeople: invitedPeople, activeConversation: conversation)
        }, cancelHandler: { [unowned self, unowned coordinator = coordinator] in
            let invitedPeople = coordinator.invitedPeople
            self.handleInviteFlowEnded(givenInvitedPeople: invitedPeople, activeConversation: conversation)
        })
    }
    
    private func handleInviteFlowEnded(givenInvitedPeople invitedPeople: [Person],
                                       activeConversation: Conversation) {
        
        if invitedPeople.isEmpty {
            // If the user didn't invite anyone to the conversation and the conversation doesn't have
            // any existing members, ask them if they'd like to delete it.
            Task {
                let peopleInConversation = await JibberMessagingClient.shared.getPeople(for: activeConversation)
                guard peopleInConversation.isEmpty else { return }
                
                self.presentDeleteConversationAlert(conversationId: activeConversation.id)
            }
        } else {
            // Add all of the invited people to the conversation.
            self.add(people: invitedPeople, to: activeConversation)
        }
    }
    
    func add(people: [Person], to conversation: Conversation) {
        let controller = ParseConversationController.controller(for: conversation)
        
        let acceptedConnections = people.compactMap { person in
            return person.connection
        }.filter { connection in
            return connection.status == .accepted
        }
        
        guard !acceptedConnections.isEmpty else { return }
        
        let members = acceptedConnections.compactMap { connection in
            return connection.nonMeUser?.objectId
        }
        do {
            try controller.addMembers(userIDs: Set(members))
            self.showPeopleAddedToast(for: acceptedConnections)
            Task {
                try? await controller.synchronize()
            }
        } catch {
            logError(error)
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
    
    func presentDeleteConversationAlert(conversationId: String?) {
        guard let conversationId = conversationId else {
            return
        }
        let controller = ParseConversationController.controller(for: conversationId)
        let memberCount = self.activeConversation?.id == conversationId
            ? self.activeConversation?.memberCount
            : controller.conversation?.memberCount
        guard let memberCount, memberCount <= 1 else { return }
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        let deleteAction = UIAlertAction(title: "Delete Conversation", style: .destructive, handler: {
            (action : UIAlertAction!) -> Void in
            do {
                try controller.deleteConversation()
            } catch {
                logError(error)
            }
            self.conversationVC.becomeFirstResponder()
        })
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: {
            (action : UIAlertAction!) -> Void in
            self.conversationVC.becomeFirstResponder()
        })
        
        alertController.addAction(deleteAction)
        alertController.addAction(cancelAction)
        
        self.conversationVC.resignFirstResponder()
        self.conversationVC.present(alertController, animated: true, completion: nil)
    }
    
    func presentConversationDetail() {
        guard let conversationId = self.activeConversation?.id else { return }
        
        let coordinator = ConversationDetailCoordinator(with: conversationId,
                                                        router: self.router,
                                                        deepLink: self.deepLink)
        self.present(coordinator) { [unowned self] result in
            guard let option = result else { return }
            
            Task.onMainActorAsync {
                switch option {
                case .conversation(let conversationId):
                    await self.conversationVC.scrollToConversation(with: conversationId, messageId: nil, animateScroll: false)
                case .message(let message):
                    await self.conversationVC.scrollToConversation(with: conversationId, messageId: message.id, animateScroll: true)
                }
            }
            
        }
    }
}
