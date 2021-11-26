//
//  ConversationsManager.swift
//  Jibber
//
//  Created by Benji Dodgson on 10/22/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat

protocol ActiveConversationable {
    var activeConversation: Conversation? { get }
}

extension ActiveConversationable {
    var activeConversation: Conversation? {
        return ConversationsManager.shared.activeConversation
    }
}

class ConversationsManager: EventsControllerDelegate {

    static let shared = ConversationsManager()

    private let controller = ChatClient.shared.eventsController()

    @Published var activeConversation: Conversation?

    init() {
        self.initialize()
    }

    private func initialize() {
        self.controller.delegate = self
    }

    func eventsController(_ controller: EventsController, didReceiveEvent event: Event) {
        switch event {
        case let event as MessageNewEvent:

            if self.activeConversation.isNil {
                Task {
                    await ToastScheduler.shared.schedule(toastType: .newMessage(event.message))
                }
            } else if let last = self.activeConversation, event.channel != last {
                Task {
                    await ToastScheduler.shared.schedule(toastType: .newMessage(event.message))
                }
            }
        case let event as ReactionNewEvent:

            guard let last = self.activeConversation, event.cid != last.cid else { return }
            Task {
                await ToastScheduler.shared.schedule(toastType: .newMessage(event.message))
            }
        default:
            break
        }
    }
}
