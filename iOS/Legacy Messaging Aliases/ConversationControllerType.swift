//
//  ConversationControllerType.swift
//  Jibber
//

import Foundation

/// A common interface for a conversation and one of its reply threads.
protocol ConversationControllerType {
    var conversation: Conversation? { get }
    var rootMessage: Message? { get }
    var messages: [Message] { get }
    var hasLoadedAllPreviousMessages: Bool { get }
}

extension ConversationControllerType {
    var isThread: Bool { self.rootMessage != nil }
    var cid: ConversationId? { self.conversation?.cid }
    var rootMessageID: String? { self.rootMessage?.id }
}

extension ParseConversationController: @MainActor ConversationControllerType {}
extension ParseMessageController: @MainActor ConversationControllerType {}
