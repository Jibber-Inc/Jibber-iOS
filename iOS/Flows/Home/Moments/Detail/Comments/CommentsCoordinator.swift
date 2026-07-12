//
//  CommentsCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/20/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Localization
import Coordinator

/// A coordinator for displaying a single conversation.
class CommentsCoordinator: InputHandlerCoordinator<Void>, DeepLinkHandler {
    
    var commentsVC: CommentsViewController {
        return self.inputHandlerViewController as! CommentsViewController
    }
    
    init(router: CoordinatorRouter,
         deepLink: DeepLinkable?,
         conversationId: String?,
         startingMessageId: String?,
         openReplies: Bool = false) {
        
        let vc = CommentsViewController(conversationId: conversationId,
                                        startingMessageId: startingMessageId,
                                        openReplies: openReplies)
        
        super.init(with: vc, router: router, deepLink: deepLink)
    }
    
    override func start() {
        super.start()
        
    }
    
    func handle(deepLink: DeepLinkable) {
        self.deepLink = deepLink
        
        guard let target = deepLink.deepLinkTarget else { return }
        
        switch target {
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
                    await self.commentsVC.scrollToConversation(with: conversationId, messageId: nil, animateScroll: false)
                }
            case .openReplies(let message):
                Task.onMainActorAsync {
                    await self.commentsVC.scrollToConversation(with: message.conversationId,
                                                               messageId: message.id,
                                                               viewReplies: true,
                                                               animateScroll: false)
                }
            case .message(let message):
                Task.onMainActorAsync {
                    await self.commentsVC.scrollToConversation(with: message.conversationId,
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
        
        Task.onMainActorAsync { [self] in
            let coordinator = ThreadCoordinator(with: message,
                                                startingReplyId: startingReplyId,
                                                router: self.router,
                                                deepLink: self.deepLink)
            
            self.present(coordinator) { [unowned self] result in
                switch result {
                case .deeplink(let deeplink):
                    self.handle(deepLink: deeplink)
                default:
                    break
                }
            }
        }
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
                    await self.commentsVC.scrollToConversation(with: conversationId,
                                                               messageId: nil,
                                                               animateScroll: false)
                }
            case .none:
                break
            }
        }
    }
}
