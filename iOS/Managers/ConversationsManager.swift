//
//  ConversationsManager.swift
//  Jibber
//

import Combine
import Foundation
import MessagingContracts
import MessagingPersistence

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
    private var latestMessagesRefreshTask: Task<Void, Never>?
    private var isLatestMessagesRefreshPending = false

    private init() {
        self.messagingChangeCancellable = NotificationCenter.default
            .publisher(for: .parseMessagingDidChange, object: ParseMessagingManager.shared)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleLatestMessagesRefresh()
                }
            }
    }

    private func scheduleLatestMessagesRefresh() {
        self.isLatestMessagesRefreshPending = true
        guard self.latestMessagesRefreshTask == nil else { return }

        self.latestMessagesRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isLatestMessagesRefreshPending, !Task.isCancelled {
                self.isLatestMessagesRefreshPending = false
                await self.refreshLatestMessages()
            }
            self.latestMessagesRefreshTask = nil
            if self.isLatestMessagesRefreshPending {
                self.scheduleLatestMessagesRefresh()
            }
        }
    }

    private func refreshLatestMessages() async {
        guard let store = ParseMessagingManager.shared.store else { return }
        let state: MessagingConversationListCacheState
        do {
            state = try await store.cachedConversationListState(pageSize: 100)
        } catch is CancellationError {
            return
        } catch {
            logError(error)
            return
        }
        guard !Task.isCancelled else { return }
        guard ParseMessagingManager.shared.store === store else { return }

        let establishesBaseline = self.knownLatestMessageIDs.isEmpty
        for entry in state.entries where !entry.conversation.isDeleted {
            guard let messageSnapshot = entry.latestMessage else { continue }
            let message = ParseMessage(snapshot: messageSnapshot)
            let previousID = self.knownLatestMessageIDs[entry.conversation.id]
            self.knownLatestMessageIDs[entry.conversation.id] = message.id
            guard !establishesBaseline,
                  previousID != nil,
                  previousID != message.id else {
                continue
            }

            let conversation = ParseConversation(
                snapshot: entry.conversation,
                members: entry.members.map(ParseConversationMember.init),
                messages: [message]
            )
            self.messageEvent = message
            self.conversationEvent = conversation
            if !message.isFromCurrentUser,
               self.activeConversation?.id != entry.conversation.id {
                Task {
                    await ToastScheduler.shared.schedule(toastType: .newMessage(message))
                }
            }
        }
    }
}
