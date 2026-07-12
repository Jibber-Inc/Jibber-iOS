//
//  FocusStatusIntentHandler.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/18/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Intents
import ParseCore
import UserNotifications

final class FocusIntentHandler: NSObject, INShareFocusStatusIntentHandling {

    private let messaging = ParseIntentMessagingService.shared

    override init() {
        Config.shared.initializeParseIfNeeded()
        super.init()
    }

    func handle(
        intent: INShareFocusStatusIntent,
        completion: @escaping (INShareFocusStatusIntentResponse) -> Void
    ) {
        guard let isFocused = intent.focusStatus?.isFocused,
              let currentUser = User.current() else {
            completion(INShareFocusStatusIntentResponse(code: .failure, userActivity: nil))
            return
        }

        let newStatus: FocusStatus = isFocused ? .focused : .available
        let shouldRecoverUnreadMessages = currentUser.focusStatus != newStatus && !isFocused

        Task {
            do {
                currentUser.focusStatus = newStatus
                try await currentUser.saveLocalThenServer()

                if shouldRecoverUnreadMessages {
                    let messages = try await self.messaging.unreadMessagesForFocusRecovery()
                    for message in messages.reversed() {
                        await self.scheduleNotification(with: message)
                    }
                }

                completion(INShareFocusStatusIntentResponse(code: .success, userActivity: nil))
            } catch {
                logError(error)
                completion(INShareFocusStatusIntentResponse(code: .failure, userActivity: nil))
            }
        }
    }

    private func scheduleNotification(with message: ParseIntentMessage) async {
        let content = UNMutableNotificationContent()
        content.title = "While you were away..."
        content.subtitle = self.getTimeAgoString(for: message.createdAt)
        let body = message.text.isEmpty ? "Sent an attachment" : message.text
        content.body = "\(message.author.givenName) said: \(body)"
        content.categoryIdentifier = "MESSAGE_NEW"
        content.threadIdentifier = message.conversationID
        content.interruptionLevel = .active
        content.setData(value: DeepLinkTarget.conversation.rawValue, for: .target)
        content.setData(value: message.author.objectID, for: .author)
        content.setData(value: message.objectID, for: .messageId)
        content.setData(value: message.conversationID, for: .conversationId)
        content.userInfo["messaging"] = [
            "author": message.author.objectID,
            "conversationId": message.conversationID,
            "deliveryType": message.deliveryType,
            "id": message.objectID,
            "sender": "parse.messaging",
            "type": "message.new",
            "version": "v1",
        ]

        let finalContent = await self.donateIncomingIntent(for: message, content: content)
        let request = UNNotificationRequest(
            identifier: message.objectID,
            content: finalContent,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logError(error)
        }
    }

    private func donateIncomingIntent(
        for message: ParseIntentMessage,
        content: UNMutableNotificationContent
    ) async -> UNNotificationContent {
        let recipients = message.participants
            .filter { $0.objectID != message.author.objectID }
            .map(\.intentPerson)
        let groupName = message.conversationTitle.flatMap { title in
            title.isEmpty ? nil : INSpeakableString(spokenPhrase: title)
        }
        let intent = INSendMessageIntent(
            recipients: recipients,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: groupName,
            conversationIdentifier: message.conversationID,
            serviceName: "Jibber",
            sender: message.author.intentPerson,
            attachments: []
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming

        do {
            try await interaction.donate()
            return try content.updating(from: intent)
        } catch {
            logError(error)
            return content
        }
    }

    private func getTimeAgoString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
