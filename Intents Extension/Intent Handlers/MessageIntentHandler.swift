//
//  MessageIntentHandler.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/18/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Intents
import ParseCore

final class MessageIntentHandler: NSObject,
                                  INSendMessageIntentHandling,
                                  INSearchForMessagesIntentHandling,
                                  INSetMessageAttributeIntentHandling {

    private let messaging = ParseIntentMessagingService.shared

    override init() {
        Config.shared.initializeParseIfNeeded()
        super.init()
    }

    // MARK: - INSendMessageIntentHandling

    func resolveRecipients(
        for intent: INSendMessageIntent,
        with completion: @escaping ([INSendMessageRecipientResolutionResult]) -> Void
    ) {
        guard let recipients = intent.recipients, !recipients.isEmpty else {
            completion([.needsValue()])
            return
        }

        let hasCanonicalConversationID = intent.conversationIdentifier?.isEmpty == false
        let results = recipients.map { recipient -> INSendMessageRecipientResolutionResult in
            if recipient.customIdentifier?.isEmpty == false || hasCanonicalConversationID {
                return .success(with: recipient)
            }
            return .unsupported()
        }
        completion(results)
    }

    func resolveContent(
        for intent: INSendMessageIntent,
        with completion: @escaping (INStringResolutionResult) -> Void
    ) {
        guard let text = intent.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            completion(.needsValue())
            return
        }
        completion(.success(with: text))
    }

    func confirm(
        intent: INSendMessageIntent,
        completion: @escaping (INSendMessageIntentResponse) -> Void
    ) {
        guard self.messaging.isAuthenticated,
              let conversationID = intent.conversationIdentifier,
              !conversationID.isEmpty else {
            completion(self.sendResponse(code: .failureRequiringAppLaunch))
            return
        }

        Task {
            do {
                try await self.messaging.requireActiveMembership(conversationID: conversationID)
                completion(self.sendResponse(code: .ready, conversationID: conversationID))
            } catch {
                completion(self.sendResponse(code: .failureMessageServiceNotAvailable))
            }
        }
    }

    func handle(
        intent: INSendMessageIntent,
        completion: @escaping (INSendMessageIntentResponse) -> Void
    ) {
        guard self.messaging.isAuthenticated else {
            completion(self.sendResponse(code: .failureRequiringAppLaunch))
            return
        }
        guard let conversationID = intent.conversationIdentifier,
              !conversationID.isEmpty,
              let content = intent.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            completion(self.sendResponse(code: .failureRequiringAppLaunch))
            return
        }

        Task {
            do {
                let message = try await self.messaging.sendText(
                    content,
                    conversationID: conversationID
                )
                let response = self.sendResponse(
                    code: .success,
                    conversationID: conversationID,
                    messageID: message.objectID
                )
                if #available(iOS 16.0, *) {
                    response.sentMessages = [message.intentMessage]
                }
                completion(response)
            } catch {
                completion(self.sendResponse(code: .failureMessageServiceNotAvailable))
            }
        }
    }

    private func sendResponse(
        code: INSendMessageIntentResponseCode,
        conversationID: String? = nil,
        messageID: String? = nil
    ) -> INSendMessageIntentResponse {
        let activity = NSUserActivity(activityType: NSStringFromClass(INSendMessageIntent.self))
        var userInfo: [String: String] = [:]
        userInfo["conversationId"] = conversationID
        userInfo["messageId"] = messageID
        activity.userInfo = userInfo
        return INSendMessageIntentResponse(code: code, userActivity: activity)
    }

    // MARK: - INSearchForMessagesIntentHandling

    func handle(
        intent: INSearchForMessagesIntent,
        completion: @escaping (INSearchForMessagesIntentResponse) -> Void
    ) {
        guard self.messaging.isAuthenticated else {
            completion(INSearchForMessagesIntentResponse(
                code: .failureRequiringAppLaunch,
                userActivity: nil
            ))
            return
        }

        Task {
            do {
                let messages = try await self.messaging.search(intent: intent)
                let response = INSearchForMessagesIntentResponse(code: .success, userActivity: nil)
                response.messages = messages.map(\.intentMessage)
                completion(response)
            } catch {
                completion(INSearchForMessagesIntentResponse(
                    code: .failureMessageServiceNotAvailable,
                    userActivity: nil
                ))
            }
        }
    }

    // MARK: - INSetMessageAttributeIntentHandling

    func handle(
        intent: INSetMessageAttributeIntent,
        completion: @escaping (INSetMessageAttributeIntentResponse) -> Void
    ) {
        guard self.messaging.isAuthenticated else {
            completion(INSetMessageAttributeIntentResponse(
                code: .failureRequiringAppLaunch,
                userActivity: nil
            ))
            return
        }
        guard let identifiers = intent.identifiers, !identifiers.isEmpty else {
            completion(INSetMessageAttributeIntentResponse(
                code: .failureMessageNotFound,
                userActivity: nil
            ))
            return
        }

        Task {
            do {
                try await self.messaging.setAttribute(intent.attribute, messageIDs: identifiers)
                completion(INSetMessageAttributeIntentResponse(code: .success, userActivity: nil))
            } catch ParseIntentMessagingService.ServiceError.unsupportedAttribute {
                completion(INSetMessageAttributeIntentResponse(
                    code: .failureMessageAttributeNotSet,
                    userActivity: nil
                ))
            } catch {
                completion(INSetMessageAttributeIntentResponse(
                    code: .failureMessageNotFound,
                    userActivity: nil
                ))
            }
        }
    }
}

// MARK: - Parse messaging bridge

/// Small, extension-safe Parse bridge. The main app's GRDB-backed repository is
/// intentionally not linked into the Siri extension; server ACLs and hooks
/// remain authoritative for every query and write here.
final class ParseIntentMessagingService {

    enum ServiceError: Error {
        case invalidResponse
        case notAuthenticated
        case objectNotFound
        case unsupportedAttribute
    }

    static let shared = ParseIntentMessagingService()

    private let maximumSearchResults = 50
    private let maximumFocusRecoveryResults = 50

    private init() {
        Config.shared.initializeParseIfNeeded()
    }

    var isAuthenticated: Bool {
        self.currentUser?.objectId?.isEmpty == false
    }

    private var currentUser: User? {
        User.current()
    }

    func requireActiveMembership(conversationID: String) async throws {
        guard let currentUser = self.currentUser else { throw ServiceError.notAuthenticated }
        let conversation = self.pointer(className: "Conversation", objectID: conversationID)
        let query = PFQuery(className: "ConversationMember")
        query.whereKey("conversation", equalTo: conversation)
        query.whereKey("user", equalTo: currentUser)
        query.whereKey("active", equalTo: true)
        _ = try await self.first(query: query)
    }

    func sendText(_ text: String, conversationID: String) async throws -> ParseIntentMessage {
        guard self.currentUser != nil else { throw ServiceError.notAuthenticated }
        try await self.requireActiveMembership(conversationID: conversationID)

        let clientMessageID = UUID().uuidString.lowercased()
        let parameters: [String: Any] = [
            "attachments": [],
            "clientCreatedAt": Date(),
            "clientMessageId": clientMessageID,
            "contentType": "text",
            "conversationId": conversationID,
            "deliveryType": "conversational",
            "expressions": [],
            "metadata": ["source": "siri-intent"],
            "text": text,
        ]

        let result: Any?
        do {
            result = try await self.callCloud(
                function: "messagingSendMessage",
                parameters: parameters
            )
        } catch let sendError {
            do {
                let recovered = try await self.callCloud(
                    function: "messagingGetMessageByClientId",
                    parameters: [
                        "clientMessageId": clientMessageID,
                        "conversationId": conversationID,
                    ]
                )
                guard recovered != nil else { throw sendError }
                result = recovered
            } catch {
                throw sendError
            }
        }
        let objectID: String
        if let message = result as? PFObject, let identifier = message.objectId {
            objectID = identifier
        } else {
            let conversation = self.pointer(className: "Conversation", objectID: conversationID)
            let recoveryQuery = PFQuery(className: "Message")
            recoveryQuery.whereKey("conversation", equalTo: conversation)
            recoveryQuery.whereKey("clientMessageId", equalTo: clientMessageID)
            objectID = try await self.first(query: recoveryQuery).objectId ?? String()
        }

        guard !objectID.isEmpty else { throw ServiceError.invalidResponse }
        let message = try await self.fetchMessage(objectID: objectID)
        guard let hydrated = try await self.hydrate(messages: [message]).first else {
            throw ServiceError.invalidResponse
        }
        return hydrated
    }

    func unreadMessagesForFocusRecovery() async throws -> [ParseIntentMessage] {
        guard let currentUser = self.currentUser else { throw ServiceError.notAuthenticated }

        let query = PFQuery(className: "MessageReceipt")
        query.whereKey("user", equalTo: currentUser)
        query.whereKey("state", notEqualTo: "read")
        query.includeKey("message")
        query.includeKey("message.author")
        query.includeKey("message.conversation")
        query.order(byDescending: "messageCreatedAt")
        query.limit = self.maximumFocusRecoveryResults

        let receipts = try await self.find(query: query)
        var seen = Set<String>()
        let messages = receipts.compactMap { receipt -> PFObject? in
            guard let message = receipt["message"] as? PFObject,
                  let messageID = message.objectId,
                  seen.insert(messageID).inserted,
                  message["isDeleted"] as? Bool != true,
                  (message["author"] as? PFUser)?.objectId != currentUser.objectId else {
                return nil
            }
            return message
        }

        return try await self.hydrate(messages: messages)
    }

    func search(intent: INSearchForMessagesIntent) async throws -> [ParseIntentMessage] {
        guard let currentUser = self.currentUser else { throw ServiceError.notAuthenticated }

        var constrainedMessageIDs = Set(intent.identifiers ?? [])
        if intent.attributes.contains(.read) || intent.attributes.contains(.unread) {
            let receiptQuery = PFQuery(className: "MessageReceipt")
            receiptQuery.whereKey("user", equalTo: currentUser)
            if intent.attributes.contains(.read) && !intent.attributes.contains(.unread) {
                receiptQuery.whereKey("state", equalTo: "read")
            } else if intent.attributes.contains(.unread) && !intent.attributes.contains(.read) {
                receiptQuery.whereKey("state", notEqualTo: "read")
            }
            receiptQuery.includeKey("message")
            receiptQuery.limit = self.maximumSearchResults * 2
            let receiptMessageIDs = Set(try await self.find(query: receiptQuery).compactMap { receipt in
                (receipt["message"] as? PFObject)?.objectId
            })
            if constrainedMessageIDs.isEmpty {
                constrainedMessageIDs = receiptMessageIDs
            } else {
                constrainedMessageIDs.formIntersection(receiptMessageIDs)
            }
            if constrainedMessageIDs.isEmpty { return [] }
        }

        let query = PFQuery(className: "Message")
        query.whereKey("isDeleted", notEqualTo: true)
        query.includeKey("author")
        query.includeKey("conversation")
        query.order(byDescending: "createdAt")
        query.limit = self.maximumSearchResults * 2

        if !constrainedMessageIDs.isEmpty {
            query.whereKey("objectId", containedIn: Array(constrainedMessageIDs))
        }
        if let conversationIDs = intent.conversationIdentifiers, !conversationIDs.isEmpty {
            let conversations = conversationIDs.map {
                self.pointer(className: "Conversation", objectID: $0)
            }
            query.whereKey("conversation", containedIn: conversations)
        }
        let senderIDs = intent.senders?.compactMap(\.customIdentifier).filter { !$0.isEmpty } ?? []
        if !senderIDs.isEmpty {
            let senders = senderIDs.map { self.pointer(className: "_User", objectID: $0) }
            query.whereKey("author", containedIn: senders)
        }
        if let startComponents = intent.dateTimeRange?.startDateComponents,
           let startDate = Calendar.current.date(from: startComponents) {
            query.whereKey("createdAt", greaterThanOrEqualTo: startDate)
        }
        if let endComponents = intent.dateTimeRange?.endDateComponents,
           let endDate = Calendar.current.date(from: endComponents) {
            query.whereKey("createdAt", lessThanOrEqualTo: endDate)
        }

        let objects = try await self.find(query: query)
        var messages = try await self.hydrate(messages: objects)

        let searchTerms = intent.searchTerms?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        if !searchTerms.isEmpty {
            messages = messages.filter { message in
                searchTerms.allSatisfy { term in
                    message.text.localizedCaseInsensitiveContains(term)
                }
            }
        }

        let recipientIDs = Set(intent.recipients?.compactMap(\.customIdentifier).filter { !$0.isEmpty } ?? [])
        if !recipientIDs.isEmpty {
            messages = messages.filter { message in
                let participantIDs = Set(message.participants.map(\.objectID))
                return recipientIDs.isSubset(of: participantIDs)
            }
        }

        return Array(messages.prefix(self.maximumSearchResults))
    }

    func setAttribute(_ attribute: INMessageAttribute, messageIDs: [String]) async throws {
        guard let currentUser = self.currentUser else { throw ServiceError.notAuthenticated }
        guard attribute == .read || attribute == .unread else {
            throw ServiceError.unsupportedAttribute
        }

        for messageID in messageIDs {
            let message = self.pointer(className: "Message", objectID: messageID)
            let query = PFQuery(className: "MessageReceipt")
            query.whereKey("message", equalTo: message)
            query.whereKey("user", equalTo: currentUser)
            let receipt = try await self.first(query: query)

            switch attribute {
            case .read:
                receipt["state"] = "read"
                receipt["readAt"] = Date()
            case .unread:
                receipt["state"] = "delivered"
                receipt.remove(forKey: "readAt")
            default:
                throw ServiceError.unsupportedAttribute
            }
            try await self.save(object: receipt)
        }
    }

    private func fetchMessage(objectID: String) async throws -> PFObject {
        let query = PFQuery(className: "Message")
        query.includeKey("author")
        query.includeKey("conversation")
        return try await self.get(query: query, objectID: objectID)
    }

    private func hydrate(messages: [PFObject]) async throws -> [ParseIntentMessage] {
        let conversationIDs = Set(messages.compactMap { message in
            (message["conversation"] as? PFObject)?.objectId
        })
        let conversationPointers = conversationIDs.map {
            self.pointer(className: "Conversation", objectID: $0)
        }

        var participantObjectsByConversationID: [String: [PFUser]] = [:]
        if !conversationPointers.isEmpty {
            let memberQuery = PFQuery(className: "ConversationMember")
            memberQuery.whereKey("conversation", containedIn: conversationPointers)
            memberQuery.whereKey("active", equalTo: true)
            memberQuery.includeKey("conversation")
            memberQuery.includeKey("user")
            memberQuery.limit = 1000
            let members = try await self.find(query: memberQuery)
            for member in members {
                guard let conversationID = (member["conversation"] as? PFObject)?.objectId,
                      let user = member["user"] as? PFUser else { continue }
                participantObjectsByConversationID[conversationID, default: []].append(user)
            }
        }

        let currentUserID = self.currentUser?.objectId
        return messages.compactMap { message in
            guard let objectID = message.objectId,
                  let conversation = message["conversation"] as? PFObject,
                  let conversationID = conversation.objectId,
                  let authorObject = message["author"] as? PFUser,
                  let author = ParseIntentPerson(user: authorObject, currentUserID: currentUserID) else {
                return nil
            }

            let participants = (participantObjectsByConversationID[conversationID] ?? [])
                .compactMap { ParseIntentPerson(user: $0, currentUserID: currentUserID) }
            return ParseIntentMessage(
                objectID: objectID,
                conversationID: conversationID,
                conversationTitle: conversation["title"] as? String,
                text: message["text"] as? String ?? String(),
                createdAt: message.createdAt ?? Date(),
                deliveryType: message["deliveryType"] as? String ?? "respectful",
                author: author,
                participants: participants
            )
        }
    }

    private func pointer(className: String, objectID: String) -> PFObject {
        PFObject(withoutDataWithClassName: className, objectId: objectID)
    }

    private func callCloud(function: String, parameters: [String: Any]) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            PFCloud.callFunction(inBackground: function, withParameters: parameters) { object, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: object)
                }
            }
        }
    }

    private func get(query: PFQuery<PFObject>, objectID: String) async throws -> PFObject {
        try await withCheckedThrowingContinuation { continuation in
            query.getObjectInBackground(withId: objectID) { object, error in
                if let object = object {
                    continuation.resume(returning: object)
                } else {
                    continuation.resume(throwing: error ?? ServiceError.objectNotFound)
                }
            }
        }
    }

    private func first(query: PFQuery<PFObject>) async throws -> PFObject {
        try await withCheckedThrowingContinuation { continuation in
            query.getFirstObjectInBackground { object, error in
                if let object = object {
                    continuation.resume(returning: object)
                } else {
                    continuation.resume(throwing: error ?? ServiceError.objectNotFound)
                }
            }
        }
    }

    private func find(query: PFQuery<PFObject>) async throws -> [PFObject] {
        try await withCheckedThrowingContinuation { continuation in
            query.findObjectsInBackground { objects, error in
                if let objects = objects {
                    continuation.resume(returning: objects)
                } else {
                    continuation.resume(throwing: error ?? ServiceError.invalidResponse)
                }
            }
        }
    }

    private func save(object: PFObject) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            object.saveInBackground { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ServiceError.invalidResponse)
                }
            }
        }
    }
}

struct ParseIntentPerson: Hashable {
    let objectID: String
    let givenName: String
    let familyName: String
    let phoneNumber: String?
    let isCurrentUser: Bool

    init?(user: PFUser, currentUserID: String?) {
        guard let objectID = user.objectId, !objectID.isEmpty else { return nil }
        self.objectID = objectID
        self.givenName = user["givenName"] as? String ?? String()
        self.familyName = user["familyName"] as? String ?? String()
        self.phoneNumber = user["phoneNumber"] as? String
        self.isCurrentUser = objectID == currentUserID
    }

    var displayName: String {
        let name = [self.givenName, self.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "Unknown" : name
    }

    var intentPerson: INPerson {
        let handle = INPersonHandle(
            value: self.phoneNumber ?? self.objectID,
            type: self.phoneNumber == nil ? .unknown : .phoneNumber
        )
        var components = PersonNameComponents()
        components.givenName = self.givenName
        components.familyName = self.familyName
        return INPerson(
            personHandle: handle,
            nameComponents: components,
            displayName: self.displayName,
            image: nil,
            contactIdentifier: nil,
            customIdentifier: self.objectID,
            isMe: self.isCurrentUser,
            suggestionType: .instantMessageAddress
        )
    }
}

struct ParseIntentMessage {
    let objectID: String
    let conversationID: String
    let conversationTitle: String?
    let text: String
    let createdAt: Date
    let deliveryType: String
    let author: ParseIntentPerson
    let participants: [ParseIntentPerson]

    var intentMessage: INMessage {
        let recipients = self.participants
            .filter { $0.objectID != self.author.objectID }
            .map(\.intentPerson)
        let groupName = self.conversationTitle.flatMap { title in
            title.isEmpty ? nil : INSpeakableString(spokenPhrase: title)
        }
        return INMessage(
            identifier: self.objectID,
            conversationIdentifier: self.conversationID,
            content: self.text,
            dateSent: self.createdAt,
            sender: self.author.intentPerson,
            recipients: recipients,
            groupName: groupName,
            messageType: .text,
            serviceName: "Jibber"
        )
    }
}
