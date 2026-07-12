//
//  NotificationService.swift
//  NotificationService
//
//  Created by Benji Dodgson on 6/18/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import UserNotifications
import Intents
import ParseCore

class NotificationService: UNNotificationServiceExtension {

    private let completionLock = NSLock()
    private var request: UNNotificationRequest?
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var requestID = UUID()
    private var didFinishRequest = false

    private var author: INPerson?
    private var recipients: [INPerson] = []
    private var conversationID: String?
    private var conversationTitle: String?
    private var messageID: String?
    private var firstPhotoURL: URL?
    private var messageDeliveryType: MessageDeliveryType?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let requestID = UUID()
        self.completionLock.lock()
        self.request = request
        self.contentHandler = contentHandler
        self.requestID = requestID
        self.didFinishRequest = false
        self.completionLock.unlock()
        self.resetContext()

        Task {
            Config.shared.initializeParseIfNeeded()

            guard let mutableContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
                self.finish(request.content, requestID: requestID)
                return
            }

            self.readIdentifiers(from: mutableContent)
            await self.loadParseMessageContext()
            await self.updateInterruptionLevel(of: mutableContent)
            await self.updateBadgeCount(of: mutableContent)
            self.finish(await self.finalizeContent(mutableContent), requestID: requestID)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        self.completionLock.lock()
        let requestID = self.requestID
        let content = self.request?.content.mutableCopy() as? UNMutableNotificationContent
        self.completionLock.unlock()
        guard let content = content else { return }

        Task {
            self.finish(await self.finalizeContent(content), requestID: requestID)
        }
    }

    private func finish(_ content: UNNotificationContent, requestID: UUID) {
        self.completionLock.lock()
        guard self.requestID == requestID, !self.didFinishRequest else {
            self.completionLock.unlock()
            return
        }
        self.didFinishRequest = true
        let handler = self.contentHandler
        self.contentHandler = nil
        self.completionLock.unlock()
        handler?(content)
    }

    private func resetContext() {
        self.author = nil
        self.recipients = []
        self.conversationID = nil
        self.conversationTitle = nil
        self.messageID = nil
        self.firstPhotoURL = nil
        self.messageDeliveryType = nil
    }

    private func readIdentifiers(from content: UNNotificationContent) {
        let messaging = content.userInfo["messaging"] as? [String: Any]
        let data = content.userInfo["data"] as? [String: Any]

        self.conversationID = messaging?["conversationId"] as? String
            ?? data?["conversationId"] as? String
            ?? content.conversationId
        self.messageID = messaging?["id"] as? String
            ?? data?["messageId"] as? String
            ?? content.messageId

        let deliveryType = messaging?["deliveryType"] as? String
            ?? data?["deliveryType"] as? String
        self.messageDeliveryType = deliveryType.flatMap(MessageDeliveryType.init(rawValue:))
    }

    private func loadParseMessageContext() async {
        guard let messageID = self.messageID,
              let message = try? await self.fetchMessage(id: messageID) else { return }

        if let deliveryType = message["deliveryType"] as? String {
            self.messageDeliveryType = MessageDeliveryType(rawValue: deliveryType)
        }

        if let conversation = message["conversation"] as? PFObject {
            self.conversationID = conversation.objectId ?? self.conversationID
            self.conversationTitle = conversation["title"] as? String
        }

        if let author = message["author"] as? PFUser,
           let authorID = author.objectId,
           let resolvedAuthor = try? await User.getObject(with: authorID) {
            self.author = resolvedAuthor.iNPerson
        }

        self.firstPhotoURL = self.photoURL(from: message)
        await self.loadRecipients()
    }

    private func fetchMessage(id: String) async throws -> PFObject {
        let query = PFQuery(className: "Message")
        query.includeKey("author")
        query.includeKey("conversation")

        return try await withCheckedThrowingContinuation { continuation in
            query.getObjectInBackground(withId: id) { object, error in
                if let object = object {
                    continuation.resume(returning: object)
                } else {
                    continuation.resume(throwing: error ?? ClientError.apiError(detail: "Message not found"))
                }
            }
        }
    }

    private func loadRecipients() async {
        guard let conversationID = self.conversationID else { return }

        let conversation = PFObject(withoutDataWithClassName: "Conversation", objectId: conversationID)
        let query = PFQuery(className: "ConversationMember")
        query.whereKey("conversation", equalTo: conversation)
        query.whereKey("active", equalTo: true)
        query.includeKey("user")

        guard let members = try? await self.find(query: query) else { return }
        let userIDs = members.compactMap { member in
            (member["user"] as? PFUser)?.objectId
        }

        guard let users = try? await User.fetchAndUpdateLocalContainer(where: userIDs, container: .users) else {
            return
        }
        self.recipients = users.compactMap(\.iNPerson)
    }

    private func find(query: PFQuery<PFObject>) async throws -> [PFObject] {
        try await withCheckedThrowingContinuation { continuation in
            query.findObjectsInBackground { objects, error in
                if let objects = objects {
                    continuation.resume(returning: objects)
                } else {
                    continuation.resume(throwing: error ?? ClientError.apiError(detail: "Query failed"))
                }
            }
        }
    }

    private func photoURL(from message: PFObject) -> URL? {
        guard let attachments = message["attachments"] as? [[String: Any]] else { return nil }

        for attachment in attachments {
            guard attachment["kind"] as? String == "image" else { continue }
            if attachment["isExpression"] as? Bool == true { continue }
            if attachment["isPreview"] as? Bool == true { continue }
            if let file = attachment["file"] as? PFFileObject,
               let url = file.url {
                return URL(string: url)
            }
        }
        return nil
    }

    private func updateInterruptionLevel(of content: UNMutableNotificationContent) async {
        guard let messageDeliveryType = self.messageDeliveryType else { return }

        switch messageDeliveryType {
        case .timeSensitive:
            content.interruptionLevel = .timeSensitive
        case .conversational:
            content.interruptionLevel = .active
        case .respectful:
            content.interruptionLevel = INFocusStatusCenter.default.focusStatus.isFocused == true
                ? .passive
                : .active
        }
    }

    private func updateBadgeCount(of content: UNMutableNotificationContent) async {
        guard self.messageDeliveryType == .timeSensitive else { return }

        let badgeNumber = self.getUserDefaultsBadgeNumber() + 1
        content.badge = badgeNumber as NSNumber
        self.setUserDefaultsBadgeNumber(to: badgeNumber)
    }

    private func finalizeContent(_ content: UNMutableNotificationContent) async -> UNNotificationContent {
        if let conversationID = self.conversationID {
            content.threadIdentifier = conversationID
            content.setData(value: conversationID, for: .conversationId)
        }
        if let messageID = self.messageID {
            content.setData(value: messageID, for: .messageId)
        }
        content.setData(value: DeepLinkTarget.conversation.rawValue, for: .target)

        if let firstPhotoURL = self.firstPhotoURL,
           let attachment = await UNNotificationAttachment.getAttachment(url: firstPhotoURL) {
            content.attachments = [attachment]
        }

        let groupName = self.conversationTitle.flatMap { title in
            title.isEmpty ? nil : INSpeakableString(spokenPhrase: title)
        }
        let incomingMessageIntent = INSendMessageIntent(
            recipients: self.recipients,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: groupName,
            conversationIdentifier: self.conversationID,
            serviceName: "Jibber",
            sender: self.author,
            attachments: []
        )

        let interaction = INInteraction(intent: incomingMessageIntent, response: nil)
        interaction.direction = .incoming

        do {
            try await interaction.donate()
            return try content.updating(from: incomingMessageIntent)
        } catch {
            logError(error)
            return content
        }
    }

    private func getUserDefaultsBadgeNumber() -> Int {
        guard let defaults = UserDefaults(suiteName: Config.shared.environment.groupId),
              let count = defaults.value(forKey: "badgeNumber") as? Int else { return 0 }
        return count
    }

    private func setUserDefaultsBadgeNumber(to number: Int) {
        guard let defaults = UserDefaults(suiteName: Config.shared.environment.groupId) else {
            logDebug("Failed to update badge number")
            return
        }
        defaults.set(number as NSNumber, forKey: "badgeNumber")
    }
}
