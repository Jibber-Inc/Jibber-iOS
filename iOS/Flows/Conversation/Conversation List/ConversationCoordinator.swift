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
import Localization
import Intents
import Coordinator

/// A coordinator for displaying a single conversation.
class ConversationCoordinator: InputHandlerCoordinator<Void>, DeepLinkHandler {
    
    var conversationVC: ConversationViewController {
        return self.inputHandlerViewController as! ConversationViewController
    }
    
    init(router: CoordinatorRouter,
         deepLink: DeepLinkable?,
         conversationId: String?,
         startingMessageId: String?,
         openReplies: Bool = false) {
        
        let vc = ConversationViewController(conversationId: conversationId,
                                            startingMessageId: startingMessageId,
                                            openReplies: openReplies)
        
        super.init(with: vc, router: router, deepLink: deepLink)
    }
    
    override func start() {
        super.start()
        
        self.conversationVC.headerVC.closeButton.didSelect { [unowned self] in
            self.finishFlow(with: ())
        }
        
        self.conversationVC.headerVC.button.didSelect { [unowned self] in
            self.presentConversationDetail()
        }
        
        self.conversationVC.dataSource.handleAddPeopleSelected = { [unowned self] in
            self.presentPeoplePicker()
        }
        
        self.conversationVC.selectionViewController.$selectedItems.mainSink { [unowned self] items in
            guard let first = items.first else { return }
            switch first {
            case .conversation(let conversationId):
                self.conversationVC.conversationId = conversationId
            }
        }.store(in: &self.cancellables)
    }
    
    func handle(deepLink: DeepLinkable) {
        self.deepLink = deepLink
        
        guard let target = deepLink.deepLinkTarget else { return }
        
        switch target {
        case .conversation:
            let messageID = deepLink.messageId
            guard let conversationId = deepLink.conversationId else { break }
            
            if conversationId == self.conversationVC.conversationId {
                Task {
                    await self.conversationVC.scrollToConversation(with: conversationId,
                                                                   messageId: messageID,
                                                                   animateScroll: false,
                                                                   animateSelection: true)
                }.add(to: self.taskPool)
            } else {
                self.conversationVC.startingMessageId = deepLink.messageId
                self.conversationVC.conversationId = conversationId 
            }
            
        case .profile:
            Task {
                guard let personId = self.deepLink?.personId,
                      let person = await PeopleStore.shared.getPerson(withPersonId: personId) else { return }
                self.presentProfile(for: person)
            }
        default:
            break
        }
    }
    
    override func presentProfile(for person: PersonType) {
        let coordinator = ProfileCoordinator(with: person, router: self.router, deepLink: self.deepLink)
        self.present(coordinator) { [unowned self] result in
            switch result {
            case .conversation(let conversationId):
                Task.onMainActorAsync {
                    await self.conversationVC.scrollToConversation(with: conversationId, messageId: nil, animateScroll: false)
                }
            case .openReplies(let message):
                Task.onMainActorAsync {
                    await self.conversationVC.scrollToConversation(with: message.conversationId,
                                                                   messageId: message.id,
                                                                   viewReplies: true,
                                                                   animateScroll: false)
                }
            case .message(let message):
                Task.onMainActorAsync {
                    await self.conversationVC.scrollToConversation(with: message.conversationId,
                                                                   messageId: message.id,
                                                                   viewReplies: false,
                                                                   animateScroll: false)
                }
            }
        }
    }
    
    override func messageContent(_ content: MessageContentView, didTapMessage message: Messageable) {
                
        if let parentId = message.parentMessageId,
            let parentMessage = JibberMessagingClient.shared.message(conversationId: message.conversationId, id: parentId) {
            self.presentThread(for: parentMessage, startingReplyId: message.id)
        } else {
            self.presentMessageDetail(for: message)
        }
    }
    
    override func messageContent(_ content: MessageContentView, didTapViewReplies message: Messageable) {
        self.presentThread(for: message, startingReplyId: nil)
    }
    
    override func presentThread(for message: Messageable, startingReplyId: String?) {
        
        let coordinator = ThreadCoordinator(with: message,
                                            startingReplyId: startingReplyId,
                                            router: self.router,
                                            deepLink: self.deepLink)
        
        self.present(coordinator) { [unowned self] result in
            switch result {
            case .conversation(let conversationId):
                self.conversationVC.conversationId = conversationId
            case .deeplink(let deeplink):
                self.handle(deepLink: deeplink)
            }
        }
    }
}

extension ConversationCoordinator: LaunchActivityHandler {
    func handle(launchActivity: LaunchActivity) {
        switch launchActivity {
        case .onboarding(let phoneNumber):
            logDebug("Launched with: \(String(describing: phoneNumber))")
        case .reservation(_), .pass(_):
            self.presentPersonConnection(for: launchActivity)
        case .deepLink(let deepLinkable):
            logDebug("Launched with: \(deepLinkable)")
        }
    }
}
