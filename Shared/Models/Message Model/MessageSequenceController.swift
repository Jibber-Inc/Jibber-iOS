//
//  MessageSequenceController.swift
//  Jibber
//
//  Created by Martin Young on 4/14/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

protocol MessageSequenceController {

    var memberCount: Int { get }
    var conversationId: String? { get }
    var messageSequence: MessageSequence? { get }
    var messageArray: [Messageable] { get }

    /// A publisher emitting a new value every time the channel changes.
    var messageSequenceChangePublisher: AnyPublisher<ParseEntityChange<MessageSequence>, Never> { get }

    /// A publisher emitting a new value every time the list of the messages matching the query changes.
    var messagesChangesPublisher: AnyPublisher<[ParseListChange<Message>], Never> { get }
}

extension MessageSequenceController {

    func getMessage(withId id: String) -> Messageable? {
        return self.messageArray.first { message in
            return message.id == id
        }
    }
}

/// An object representing a controller for a null message sequence. It will have no cid and an empty array of messages.
struct EmptyMessageSequenceController: MessageSequenceController {

    var memberCount: Int {
        return 0
    }
    
    var conversationId: String? = nil
    var messageSequence: MessageSequence? = nil
    var messageArray: [Messageable] = []

    var messageSequenceChangePublisher: AnyPublisher<ParseEntityChange<MessageSequence>, Never>
    = PassthroughSubject<ParseEntityChange<MessageSequence>, Never>().eraseToAnyPublisher()

    var messagesChangesPublisher: AnyPublisher<[ParseListChange<Message>], Never>
    = PassthroughSubject<[ParseListChange<Message>], Never>().eraseToAnyPublisher()

}

extension ParseConversationController: @MainActor MessageSequenceController {}
extension ParseMessageController: @MainActor MessageSequenceController {}
