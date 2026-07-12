//
//  MessageDetailCoordinator.swift
//  Jibber
//
//  Created by Martin Young on 2/24/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Coordinator

enum MessageDetailResult {
    case message(Messageable)
    case reply(String)
    case conversation(String)
    case none
}

class MessageDetailCoordinator: PresentableCoordinator<MessageDetailResult> {

    private lazy var messageVC = MessageDetailViewController(message: self.message)

    private let message: Messageable

    init(with message: Messageable,
         router: CoordinatorRouter,
         deepLink: DeepLinkable?) {

        self.message = message

        super.init(router: router, deepLink: deepLink)
    }
    
    override func start() {
        super.start()
        
        self.messageVC.messageContent?.delegate = self
        
        self.messageVC.$selectedItems
            .removeDuplicates()
            .mainSink { items in
            guard let first = items.first else { return }
            switch first {
            case .option(let type):
                switch type {
                case .viewThread:
                    self.finishFlow(with: .message(self.message))
                case .edit:
                    self.presentAlert(for: type)
                case .pin:
                    self.updatePin(shouldPin: true)
                case .unpin:
                    self.updatePin(shouldPin: false)
                case .quote:
                    self.presentAlert(for: type)
                case .more:
                    break
                }
            case .read(let model):
                Task {
                    guard let authorId = model.authorId, let author = await PeopleStore.shared.getPerson(withPersonId: authorId) else { return }
                    self.presentProfile(for: author)
                }
            case .expression:
                break 
            case .metadata(_):
                break
            case .more(_):
                break
            }
        }.store(in: &self.cancellables)
        
        self.messageVC.blurView.didSelect { [unowned self] in
            self.finishFlow(with: .none)
        }
        
        self.messageVC.dataSource.didTapDelete = { [unowned self] in
            self.handleDelete()
        }
        
        self.messageVC.dataSource.didTapEdit = { [unowned self] in
            self.handleEdit()
        }
    }

    override func toPresentable() -> PresentableCoordinator<Messageable?>.DismissableVC {
        return self.messageVC
    }
    
    private func handleEdit() {
        self.presentAlert(for: .edit)
    }
    
    private func updatePin(shouldPin: Bool) {
        guard let controller = self.messageVC.messageController else { return }
        
        Task {
            if shouldPin {
                try? controller.pinMessage()
            } else {
                try? controller.unpinMessage()
            }
        }
    }
    
    private func handleDelete() {
        Task {
            let controller = MessageController.controller(for: self.message)
            try? controller?.deleteMessage()
            
            await ToastScheduler.shared.schedule(toastType: .success(ImageSymbol.trash, "Message Deleted"))
            
            self.finishFlow(with: .none)
        }
    }
    
    private func presentAlert(for option: MessageDetailDataSource.OptionType) {
        
        let alertController = UIAlertController(title: option.title,
                                                message: "(Coming Soon)",
                                                preferredStyle: .alert)

        let cancelAction = UIAlertAction(title: "Got it", style: .cancel, handler: {
            (action : UIAlertAction!) -> Void in
        })

        alertController.addAction(cancelAction)
        self.messageVC.present(alertController, animated: true, completion: nil)
    }
    
    func presentProfile(for person: PersonType) {
        self.removeChild()

        let coordinator = ProfileCoordinator(with: person, router: self.router, deepLink: self.deepLink)
        
        self.addChildAndStart(coordinator) { [unowned self] result in
            self.messageVC.dismiss(animated: true) { [unowned self] in
                switch result {
                case .conversation(let conversationId):
                    self.finishFlow(with: .conversation(conversationId))
                default:
                    break 
                }
            }
        }
        
        self.router.present(coordinator, source: self.messageVC, cancelHandler: nil)
    }
}

extension MessageDetailCoordinator: MessageContentDelegate {
    
    func messageContent(_ content: MessageContentView, didTapViewReplies message: Messageable) {
        self.finishFlow(with: .reply(message.id))
    }
    
    func messageContent(_ content: MessageContentView, didTapMessage message: Messageable) {
        self.finishFlow(with: .message(self.message))
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
    
    func messageContent(_ content: MessageContentView, didTapAddExpressionForMessage message: Messageable) {
        self.presentExpressionCreation(for: message)
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
        self.addChildAndStart(coordinator) { [unowned self] result in
            switch result {
            case .reply(let message):
                self.messageVC.dismiss(animated: true) { [unowned self] in 
                    self.finishFlow(with: .message(message))
                }
            case .none:
                break
            }
        }
        self.router.present(coordinator, source: self.messageVC, cancelHandler: nil)
    }
    
    func presentExpressionCreation(for message: Messageable) {
        let coordinator = ExpressionCoordinator(router: self.router,
                                                deepLink: self.deepLink)
        self.addChildAndStart(coordinator) { [unowned self] result in
            guard let expression = result else { return }
            
            expression.emotions.forEach { emotion in
                AnalyticsManager.shared.trackEvent(type: .emotionSelected,
                                                   properties: ["value": emotion.rawValue])
            }
            
            let controller = MessageController.controller(for: message)
            
            Task {
                do {
                    try await controller?.add(expression: expression)
                } catch {
                    logError(error)
                }
            }
            self.messageVC.dismiss(animated: true)
        }
        self.router.present(coordinator, source: self.messageVC, cancelHandler: nil)
    }
}
