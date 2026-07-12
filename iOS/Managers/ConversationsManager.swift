//
//  ConversationsManager.swift
//  Jibber
//

import Combine
import Foundation

@MainActor
protocol ActiveConversationable {
    var activeConversation: Conversation? { get }
}

extension ActiveConversationable {
    var activeConversation: Conversation? {
        ConversationsManager.shared.activeConversation
    }
}

@MainActor
final class ConversationsManager {

    static let shared = ConversationsManager()

    @Published var activeController: MessageSequenceController?
    @Published var activeConversation: Conversation?

    @Published private(set) var messageEvent: Message?
    @Published private(set) var conversationEvent: Conversation?

    private var knownLatestMessageIDs: [String: String] = [:]
    private var messagingChangeCancellable: AnyCancellable?

    private init() {
        self.messagingChangeCancellable = NotificationCenter.default
            .publisher(for: .parseMessagingDidChange, object: ParseMessagingManager.shared)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLatestMessages()
            }
    }

    private func refreshLatestMessages() {
        guard let store = ParseMessagingManager.shared.store,
              let page = try? store.cachedConversations(before: nil, pageSize: 100) else {
            return
        }

        let establishesBaseline = self.knownLatestMessageIDs.isEmpty
        for snapshot in page.items where !snapshot.isDeleted {
            guard let messageSnapshot = try? store.cachedMessages(
                conversationID: snapshot.id,
                before: nil,
                pageSize: 1
            ).items.first else {
                continue
            }

            let message = ParseMessage(snapshot: messageSnapshot)
            let previousID = self.knownLatestMessageIDs[snapshot.id]
            self.knownLatestMessageIDs[snapshot.id] = message.id
            guard !establishesBaseline,
                  previousID != nil,
                  previousID != message.id else {
                continue
            }

            let conversation = JibberMessagingClient.shared.conversation(for: snapshot.id)
            self.messageEvent = message
            self.conversationEvent = conversation
            if !message.isFromCurrentUser,
               self.activeConversation?.id != snapshot.id {
                Task {
                    await ToastScheduler.shared.schedule(toastType: .newMessage(message))
                }
            }
        }
    }
}
