//
//  ConversationThreadCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/17/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Coordinator

enum ThreadResult {
    case conversation(String)
    case deeplink(DeepLinkable)
}

class ThreadCoordinator: InputHandlerCoordinator<ThreadResult>, DeepLinkHandler {
    
    var threadVC: ThreadViewController {
        return self.inputHandlerViewController as! ThreadViewController
    }

    init(with message: Messageable,
         startingReplyId: String?,
         router: CoordinatorRouter,
         deepLink: DeepLinkable?) {
        
        let vc = ThreadViewController(message: message, startingReplyId: startingReplyId)

        super.init(with: vc, router: router, deepLink: deepLink)
    }

    override func toPresentable() -> PresentableCoordinator<Void>.DismissableVC {
        return self.threadVC
    }
    
    override func start() {
        super.start()
        
        self.threadVC.messageContent?.delegate = self 
        
        self.threadVC.$selectedItems.mainSink { [unowned self] items in
            guard let first = items.first,
                  case MessageSequenceItem.message(let messageID, _) = first,
                  let conversationID = self.threadVC.conversationController?.conversationID.rawValue else { return }
            
            self.presentMessageDetail(for: conversationID, messageId: messageID)
        }.store(in: &self.cancellables)
    }
    
    /// The currently running task that is loading.
    private var loadTask: Task<Void, Never>?
    
    override func scrollToUnreadMessage() {
        // Find the oldest unread message.
        guard let conversation = self.threadVC.messageController.conversation,
              let unreadMessage = self.threadVC.messageController.replies.reversed().first(where: { message in
                  return !message.isFromCurrentUser && !message.isConsumedByMe
              }) else { return }
        
        self.loadTask?.cancel()
        
        self.loadTask = Task { [weak self] in
            guard let self else { return }
            await self.inputHandlerViewController.scrollToConversation(with: conversation.id,
                                                                       messageId: unreadMessage.id,
                                                                       viewReplies: false,
                                                                       animateScroll: true,
                                                                       animateSelection: true)
        }
    }
    
    override func presentProfile(for person: PersonType) {
        let coordinator = ProfileCoordinator(with: person, router: self.router, deepLink: self.deepLink)
        self.present(coordinator) { [unowned self] result in
            switch result {
            case .conversation(let conversationId):
                self.finishFlow(with: .conversation(conversationId))
            default:
                break 
            }
        }
    }
    
    func presentMessageDetail(for conversationId: String, messageId: String) {
        guard let message = self.threadVC.messageController.getMessage(withId: messageId),
              message.conversationId == conversationId else { return }
        let coordinator = MessageDetailCoordinator(with: message,
                                                   router: self.router,
                                                   deepLink: self.deepLink)
        
        self.present(coordinator) { [unowned self] result in
            switch result {
            case .message(_):
                break
            case .reply(_):
                break
            case .conversation(let conversation):
                self.finishFlow(with: .conversation(conversation))
            case .none:
                break
            }
        }
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
        case .conversation:
            self.finishFlow(with: .deeplink(deepLink))
        default:
            break
        }
    }
    
    override func presentMediaFlow(for mediaItems: [MediaItem],
                                   startingItem: MediaItem?,
                                   message: Messageable) {
        
        let coordinator = MediaCoordinator(items: mediaItems,
                                           startingItem: startingItem,
                                           message: message,
                                           router: self.router,
                                           deepLink: self.deepLink)
        self.threadVC.isPresentingImage = true
        self.present(coordinator) { [unowned self] _ in
            self.threadVC.isPresentingImage = false
        } cancelHandler: { [unowned self] in
            self.threadVC.isPresentingImage = false
        }
    }
}
