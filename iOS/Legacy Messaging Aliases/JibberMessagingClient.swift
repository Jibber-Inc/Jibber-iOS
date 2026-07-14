//
//  JibberMessagingClient.swift
//  Jibber
//
//  Application facade backed entirely by Parse messaging.

import Foundation
import MessagingContracts
import MessagingPersistence
import ParseCore

private final class WeakControllerBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

@MainActor
final class JibberMessagingClient {

    static let shared = JibberMessagingClient()

    private let manager = ParseMessagingManager.shared
    private var conversationControllers: [String: WeakControllerBox<ParseConversationController>] = [:]
    private var messageControllers: [String: WeakControllerBox<ParseMessageController>] = [:]

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

    func conversationController(for conversationID: String) -> ConversationController? {
        guard !conversationID.isEmpty else { return nil }
        self.pruneReleasedControllers()
        if let controller = self.conversationControllers[conversationID]?.value {
            return controller
        }
        self.conversationControllers[conversationID] = nil
        let controller = ParseConversationController(conversationID: conversationID)
        self.conversationControllers[conversationID] = WeakControllerBox(controller)
        return controller
    }

    func messageController(for conversationID: String, id messageID: String) -> MessageController? {
        guard !conversationID.isEmpty, !messageID.isEmpty else { return nil }
        self.pruneReleasedControllers()
        let key = "\(conversationID):\(messageID)"
        if let controller = self.messageControllers[key]?.value {
            return controller
        }
        self.messageControllers[key] = nil
        let controller = ParseMessageController(
            conversationID: conversationID,
            messageID: messageID
        )
        self.messageControllers[key] = WeakControllerBox(controller)
        return controller
    }

    private func pruneReleasedControllers() {
        self.conversationControllers = self.conversationControllers.filter { $0.value.value != nil }
        self.messageControllers = self.messageControllers.filter { $0.value.value != nil }
    }

    func messageController(for message: Messageable) -> MessageController? {
        self.messageController(for: message.conversationId, id: message.id)
    }

    func message(conversationId: String, id messageID: String) async -> Messageable? {
        guard let snapshot = try? await self.manager.cachedMessage(
            conversationID: conversationId,
            id: messageID
        ) else { return nil }
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
        let members = try? await self.manager.members(conversationID: snapshot.id)
        AnalyticsManager.shared.trackEvent(type: .conversationCreated, properties: nil)
        return ParseConversation(
            snapshot: snapshot,
            members: members?.map(ParseConversationMember.init) ?? []
        )
    }
}
