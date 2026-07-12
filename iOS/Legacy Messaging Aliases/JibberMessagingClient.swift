//
//  JibberMessagingClient.swift
//  Jibber
//
//  Application facade backed entirely by Parse messaging.

import Foundation
import MessagingContracts
import MessagingPersistence
import ParseCore

@MainActor
final class JibberMessagingClient {

    static let shared = JibberMessagingClient()

    private let manager = ParseMessagingManager.shared
    private var conversationControllers: [String: ParseConversationController] = [:]
    private var messageControllers: [String: ParseMessageController] = [:]

    private init() {}

    var isConnected: Bool { self.manager.isInitialized }

    var isConnectedToCurrentUser: Bool {
        self.manager.authenticatedUserID == User.current()?.objectId
    }

    func initialize(for user: User) async throws {
        try await self.manager.initialize(for: user)
    }

    func disconnect() {
        self.conversationControllers.removeAll()
        self.messageControllers.removeAll()
    }

    func conversation(for conversationID: String) -> Conversation? {
        guard !conversationID.isEmpty,
              let store = self.manager.store,
              let snapshot = try? ParseMessagingControllerSupport.cachedConversation(
                id: conversationID,
                manager: self.manager
              ) else {
            return nil
        }

        let members = (try? store.cachedMembers(conversationID: conversationID))?
            .map(ParseConversationMember.init) ?? []
        let messages = (try? store.cachedMessages(
            conversationID: conversationID,
            before: nil,
            pageSize: 100
        ).items.map { ParseMessage(snapshot: $0) }) ?? []
        return ParseConversation(
            snapshot: snapshot,
            members: members,
            messages: messages,
            pinnedMessages: messages.filter(\.isPinned)
        )
    }

    func conversationController(for conversationID: String) -> ConversationController? {
        guard !conversationID.isEmpty else { return nil }
        if let controller = self.conversationControllers[conversationID] {
            return controller
        }
        let controller = ParseConversationController(conversationID: conversationID)
        self.conversationControllers[conversationID] = controller
        return controller
    }

    func messageController(for conversationID: String, id messageID: String) -> MessageController? {
        guard !conversationID.isEmpty, !messageID.isEmpty else { return nil }
        let key = "\(conversationID):\(messageID)"
        if let controller = self.messageControllers[key] {
            return controller
        }
        let controller = ParseMessageController(
            conversationID: conversationID,
            messageID: messageID
        )
        self.messageControllers[key] = controller
        return controller
    }

    func messageController(for message: Messageable) -> MessageController? {
        self.messageController(for: message.conversationId, id: message.id)
    }

    func message(conversationId: String, id messageID: String) -> Messageable? {
        guard let store = self.manager.store else { return nil }
        let snapshot = (try? store.cachedMessage(objectID: messageID))
            ?? (try? store.cachedMessage(clientMessageID: messageID))
        guard let snapshot, snapshot.conversationID == conversationId else { return nil }
        return ParseMessage(snapshot: snapshot)
    }

    func getPeople(for conversation: Conversation) async -> [PersonType] {
        var people = conversation.activeMembers.compactMap(\.person)
        var seen = Set(people.map(\.personId))

        for (reservationID, reservation) in PeopleStore.shared.unclaimedReservations {
            guard reservation.conversationCid == conversation.id,
                  let contactID = reservation.contactId,
                  !seen.contains(contactID),
                  let person = await PeopleStore.shared.getPerson(withPersonId: contactID) else {
                _ = reservationID
                continue
            }
            seen.insert(person.personId)
            people.append(person)
        }
        return people
    }

    func createNewConversation() async throws -> Conversation? {
        guard let userID = User.current()?.objectId else {
            throw ParseMessagingCompatibilityError.missingCurrentUser
        }
        let snapshot = try await self.manager.createConversation(
            memberIDs: [userID],
            type: .direct,
            clientConversationID: UUID().uuidString.lowercased(),
            contextKey: nil
        )
        _ = try? await self.manager.members(conversationID: snapshot.id)
        AnalyticsManager.shared.trackEvent(type: .conversationCreated, properties: nil)
        return self.conversation(for: snapshot.id)
            ?? ParseConversation(snapshot: snapshot)
    }
}
