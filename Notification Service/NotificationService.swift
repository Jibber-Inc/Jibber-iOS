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

/// Moves one legacy framework value into one asynchronous consumer. The
/// notification service never reads a wrapped value again after launching the
/// corresponding task or resuming the continuation.
private nonisolated struct UncheckedSendableTransfer<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Mutable while a single notification-processing task owns it. None of these
/// legacy framework values are shared between requests or accessed by the
/// expiry callback.
private nonisolated struct NotificationRequestContext: @unchecked Sendable {
    var author: INPerson?
    var recipients: [INPerson] = []
    var conversationID: String?
    var conversationTitle: String?
    var messageID: String?
    var firstPhotoURL: URL?
    var messageDeliveryType: MessageDeliveryType?
}

class NotificationService: UNNotificationServiceExtension {

    private let completionLock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var requestID = UUID()
    private var didFinishRequest = true
    private var processingTask: Task<Void, Never>?
    private var latestBestAttemptContent: UNNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let requestID = UUID()

        var previousTask: Task<Void, Never>?
        var previousHandler: ((UNNotificationContent) -> Void)?
        var previousContent: UNNotificationContent?
        self.completionLock.lock()
        previousTask = self.processingTask
        if !self.didFinishRequest {
            previousHandler = self.contentHandler
            previousContent = self.latestBestAttemptContent
        }
        self.contentHandler = contentHandler
        self.requestID = requestID
        self.didFinishRequest = false
        self.processingTask = nil
        self.latestBestAttemptContent = request.content
        self.completionLock.unlock()

        previousTask?.cancel()
        if let previousHandler, let previousContent {
            previousHandler(previousContent)
        }

        let service = UncheckedSendableTransfer(self)
        let request = UncheckedSendableTransfer(request)
        let task = Task {
            let service = service.value
            let request = request.value

            guard !Task.isCancelled, service.isRequestActive(requestID) else { return }
            Config.shared.initializeParseIfNeeded()
            guard !Task.isCancelled, service.isRequestActive(requestID) else { return }

            guard let mutableContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
                service.finish(request.content, requestID: requestID)
                return
            }

            var context = service.readIdentifiers(from: mutableContent)
            context = await service.loadParseMessageContext(context)
            guard !Task.isCancelled, service.isRequestActive(requestID) else { return }

            await service.updateInterruptionLevel(
                of: mutableContent,
                deliveryType: context.messageDeliveryType
            )
            guard !Task.isCancelled,
                  service.updateBestAttemptContent(mutableContent, requestID: requestID) else { return }

            service.updateBadgeCount(
                of: mutableContent,
                deliveryType: context.messageDeliveryType,
                requestID: requestID
            )
            guard !Task.isCancelled, service.isRequestActive(requestID) else { return }

            service.applyIdentifiers(from: context, to: mutableContent)
            guard service.updateBestAttemptContent(mutableContent, requestID: requestID) else { return }

            if let firstPhotoURL = context.firstPhotoURL {
                guard !Task.isCancelled, service.isRequestActive(requestID) else { return }
                if let attachment = await UNNotificationAttachment.getAttachment(url: firstPhotoURL) {
                    guard !Task.isCancelled, service.isRequestActive(requestID) else { return }
                    mutableContent.attachments = [attachment]
                    guard service.updateBestAttemptContent(mutableContent, requestID: requestID) else { return }
                }
            }

            guard !Task.isCancelled, service.isRequestActive(requestID) else { return }
            let finalizedContent = await service.donateIncomingIntent(
                for: mutableContent,
                context: context
            )
            guard !Task.isCancelled, service.isRequestActive(requestID) else { return }
            service.finish(finalizedContent, requestID: requestID)
        }
        self.retainProcessingTask(task, requestID: requestID)
    }

    override func serviceExtensionTimeWillExpire() {
        var task: Task<Void, Never>?
        var handler: ((UNNotificationContent) -> Void)?
        var content: UNNotificationContent?

        self.completionLock.lock()
        if !self.didFinishRequest,
           let currentHandler = self.contentHandler,
           let bestAttemptContent = self.latestBestAttemptContent {
            self.didFinishRequest = true
            task = self.processingTask
            handler = currentHandler
            content = bestAttemptContent
            self.processingTask = nil
            self.contentHandler = nil
        }
        self.completionLock.unlock()

        task?.cancel()
        if let handler, let content {
            handler(content)
        }
    }

    private func finish(_ content: UNNotificationContent, requestID: UUID) {
        let snapshot = self.immutableSnapshot(of: content)

        self.completionLock.lock()
        guard self.requestID == requestID, !self.didFinishRequest else {
            self.completionLock.unlock()
            return
        }
        self.didFinishRequest = true
        self.latestBestAttemptContent = snapshot
        let handler = self.contentHandler
        self.contentHandler = nil
        self.processingTask = nil
        self.completionLock.unlock()
        handler?(snapshot)
    }

    private func retainProcessingTask(_ task: Task<Void, Never>, requestID: UUID) {
        self.completionLock.lock()
        guard self.requestID == requestID, !self.didFinishRequest else {
            self.completionLock.unlock()
            task.cancel()
            return
        }
        self.processingTask = task
        self.completionLock.unlock()
    }

    private func isRequestActive(_ requestID: UUID) -> Bool {
        self.completionLock.lock()
        let isActive = self.requestID == requestID && !self.didFinishRequest
        self.completionLock.unlock()
        return isActive
    }

    @discardableResult
    private func updateBestAttemptContent(_ content: UNNotificationContent,
                                          requestID: UUID) -> Bool {
        let snapshot = self.immutableSnapshot(of: content)

        self.completionLock.lock()
        guard self.requestID == requestID, !self.didFinishRequest else {
            self.completionLock.unlock()
            return false
        }
        self.latestBestAttemptContent = snapshot
        self.completionLock.unlock()
        return true
    }

    private func immutableSnapshot(of content: UNNotificationContent) -> UNNotificationContent {
        content.copy() as? UNNotificationContent ?? content
    }

    private func readIdentifiers(from content: UNNotificationContent) -> NotificationRequestContext {
        var context = NotificationRequestContext()
        let messaging = content.userInfo["messaging"] as? [String: Any]
        let data = content.userInfo["data"] as? [String: Any]

        context.conversationID = messaging?["conversationId"] as? String
            ?? data?["conversationId"] as? String
            ?? content.conversationId
        context.messageID = messaging?["id"] as? String
            ?? data?["messageId"] as? String
            ?? content.messageId

        let deliveryType = messaging?["deliveryType"] as? String
            ?? data?["deliveryType"] as? String
        context.messageDeliveryType = deliveryType.flatMap(MessageDeliveryType.init(rawValue:))
        return context
    }

    private func loadParseMessageContext(_ initialContext: NotificationRequestContext) async -> NotificationRequestContext {
        var context = initialContext
        guard !Task.isCancelled,
              let messageID = context.messageID,
              let message = try? await self.fetchMessage(id: messageID),
              !Task.isCancelled else { return context }

        if let deliveryType = message["deliveryType"] as? String {
            context.messageDeliveryType = MessageDeliveryType(rawValue: deliveryType)
        }

        if let conversation = message["conversation"] as? PFObject {
            context.conversationID = conversation.objectId ?? context.conversationID
            context.conversationTitle = conversation["title"] as? String
        }

        if let author = message["author"] as? PFUser,
           let authorID = author.objectId,
           !Task.isCancelled,
           let resolvedAuthor = try? await User.getObject(with: authorID) {
            context.author = resolvedAuthor.iNPerson
        }

        guard !Task.isCancelled else { return context }
        context.firstPhotoURL = self.photoURL(from: message)
        context.recipients = await self.loadRecipients(conversationID: context.conversationID)
        return context
    }

    private func fetchMessage(id: String) async throws -> PFObject {
        let query = PFQuery(className: "Message")
        query.includeKey("author")
        query.includeKey("conversation")

        let transfer: UncheckedSendableTransfer<PFObject> = try await withCheckedThrowingContinuation { continuation in
            query.getObjectInBackground(withId: id) { object, error in
                if let object = object {
                    continuation.resume(returning: UncheckedSendableTransfer(object))
                } else {
                    continuation.resume(throwing: error ?? ClientError.apiError(detail: "Message not found"))
                }
            }
        }
        return transfer.value
    }

    private func loadRecipients(conversationID: String?) async -> [INPerson] {
        guard !Task.isCancelled, let conversationID else { return [] }

        let conversation = PFObject(withoutDataWithClassName: "Conversation", objectId: conversationID)
        let query = PFQuery(className: "ConversationMember")
        query.whereKey("conversation", equalTo: conversation)
        query.whereKey("active", equalTo: true)
        query.includeKey("user")

        guard let members = try? await self.find(query: query), !Task.isCancelled else { return [] }
        let userIDs = members.compactMap { member in
            (member["user"] as? PFUser)?.objectId
        }

        guard let users = try? await User.fetchAndUpdateLocalContainer(where: userIDs, container: .users) else {
            return []
        }
        guard !Task.isCancelled else { return [] }
        return users.compactMap(\.iNPerson)
    }

    private func find(query: PFQuery<PFObject>) async throws -> [PFObject] {
        let transfer: UncheckedSendableTransfer<[PFObject]> = try await withCheckedThrowingContinuation { continuation in
            query.findObjectsInBackground { objects, error in
                if let objects = objects {
                    continuation.resume(returning: UncheckedSendableTransfer(objects))
                } else {
                    continuation.resume(throwing: error ?? ClientError.apiError(detail: "Query failed"))
                }
            }
        }
        return transfer.value
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

    private func updateInterruptionLevel(of content: UNMutableNotificationContent,
                                         deliveryType: MessageDeliveryType?) async {
        guard let deliveryType else { return }

        switch deliveryType {
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

    private func updateBadgeCount(of content: UNMutableNotificationContent,
                                  deliveryType: MessageDeliveryType?,
                                  requestID: UUID) {
        guard deliveryType == .timeSensitive else { return }

        self.completionLock.lock()
        guard self.requestID == requestID, !self.didFinishRequest else {
            self.completionLock.unlock()
            return
        }
        let badgeNumber = self.getUserDefaultsBadgeNumber() + 1
        content.badge = badgeNumber as NSNumber
        self.setUserDefaultsBadgeNumber(to: badgeNumber)
        self.latestBestAttemptContent = self.immutableSnapshot(of: content)
        self.completionLock.unlock()
    }

    private func applyIdentifiers(from context: NotificationRequestContext,
                                  to content: UNMutableNotificationContent) {
        if let conversationID = context.conversationID {
            content.threadIdentifier = conversationID
            content.setData(value: conversationID, for: .conversationId)
        }
        if let messageID = context.messageID {
            content.setData(value: messageID, for: .messageId)
        }
        content.setData(value: DeepLinkTarget.conversation.rawValue, for: .target)
    }

    private func donateIncomingIntent(for content: UNMutableNotificationContent,
                                      context: NotificationRequestContext) async -> UNNotificationContent {
        let groupName = context.conversationTitle.flatMap { title in
            title.isEmpty ? nil : INSpeakableString(spokenPhrase: title)
        }
        let incomingMessageIntent = INSendMessageIntent(
            recipients: context.recipients,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: groupName,
            conversationIdentifier: context.conversationID,
            serviceName: "Jibber",
            sender: context.author,
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
