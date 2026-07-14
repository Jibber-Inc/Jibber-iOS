//
//  ParseMessagingControllerSupport.swift
//  Jibber
//

import Foundation
import Intents
import MessagingContracts
import MessagingPersistence
import ParseCore

@MainActor
enum ParseMessagingControllerSupport {

    static func merge(
        _ existing: [MessagingMessageSnapshot],
        with incoming: [MessagingMessageSnapshot]
    ) -> [MessagingMessageSnapshot] {
        var byStableID = Dictionary(uniqueKeysWithValues: existing.map { ($0.stableID, $0) })
        for snapshot in incoming {
            byStableID[snapshot.stableID] = snapshot
        }
        return byStableID.values.sorted { lhs, rhs in
            if lhs.sortDate == rhs.sortDate {
                return lhs.stableID > rhs.stableID
            }
            return lhs.sortDate > rhs.sortDate
        }
    }

    static func rootMessages(
        from snapshots: [MessagingMessageSnapshot]
    ) -> [ParseMessage] {
        var repliesByParentID: [String: [MessagingMessageSnapshot]] = [:]
        var roots: [MessagingMessageSnapshot] = []
        roots.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            if let parentID = snapshot.replyToMessageID {
                repliesByParentID[parentID, default: []].append(snapshot)
            } else {
                roots.append(snapshot)
            }
        }

        return roots.map { root in
            var replySnapshots = repliesByParentID[root.stableID] ?? []
            if let objectID = root.objectID, objectID != root.stableID {
                replySnapshots.append(contentsOf: repliesByParentID[objectID] ?? [])
            }
            return ParseMessage(
                snapshot: root,
                replies: replySnapshots.map { ParseMessage(snapshot: $0) }
            )
        }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func replies(
        to root: MessagingMessageSnapshot,
        from snapshots: [MessagingMessageSnapshot]
    ) -> [ParseMessage] {
        snapshots
            .filter {
                $0.replyToMessageID == root.objectID || $0.replyToMessageID == root.stableID
            }
            .map { ParseMessage(snapshot: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func serverMessageID(
        for identifier: String,
        in snapshots: [MessagingMessageSnapshot]
    ) throws -> String {
        guard let snapshot = snapshots.first(where: {
            $0.stableID == identifier || $0.objectID == identifier
        }) else {
            throw ParseMessagingCompatibilityError.messageNotFound(identifier)
        }
        guard let objectID = snapshot.objectID else {
            throw ParseMessagingCompatibilityError.messageHasNotReachedServer(identifier)
        }
        return objectID
    }

    static func currentMember(
        in members: [ParseConversationMember]
    ) throws -> ParseConversationMember {
        guard let member = members.first(where: \.isCurrentUser) else {
            throw ParseMessagingCompatibilityError.missingCurrentMember
        }
        return member
    }
}

@MainActor
enum ParseOutgoingMessageHooks {

    static func messageWasQueued(
        sendable: MessageSendable,
        conversation: ParseConversation?,
        members: [ParseConversationMember],
        isReply: Bool
    ) async {
        if sendable.expression != nil {
            AchievementsManager.shared.createIfNeeded(with: .firstExpression)
        }
        if isReply {
            AchievementsManager.shared.createIfNeeded(with: .firstReply)
            AnalyticsManager.shared.trackEvent(type: .replySent, properties: nil)
        } else {
            AchievementsManager.shared.createIfNeeded(with: .firstMessage)
            AnalyticsManager.shared.trackEvent(type: .messageSent, properties: nil)
        }

        await self.donateIntent(
            sendable: sendable,
            conversation: conversation,
            members: members
        )
        await self.presentQueuedToast(deliveryType: sendable.deliveryType)
    }

    private static func donateIntent(
        sendable: MessageSendable,
        conversation: ParseConversation?,
        members: [ParseConversationMember]
    ) async {
        guard case .text(let text) = sendable.kind else { return }
        let activeUserIDs = Set(members.filter(\.isActive).map(\.userID))
        let recipients = PeopleStore.shared.usersArray
            .filter { user in
                guard let objectID = user.objectId else { return false }
                return activeUserIDs.contains(objectID)
            }
            .compactMap(\.iNPerson)
        let sender = recipients.first(where: \.isMe)
        let groupName = conversation?.title.map {
            INSpeakableString(
                vocabularyIdentifier: "",
                spokenPhrase: $0,
                pronunciationHint: nil
            )
        }
        let intent = INSendMessageIntent(
            recipients: recipients,
            outgoingMessageType: .outgoingMessageText,
            content: text,
            speakableGroupName: groupName,
            conversationIdentifier: conversation?.id,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        try? await interaction.donate()
    }

    private static func presentQueuedToast(deliveryType: MessageDeliveryType) async {
        switch deliveryType {
        case .timeSensitive:
            await ToastScheduler.shared.schedule(
                toastType: .success(
                    deliveryType.symbol,
                    "Will notify all members of this conversation."
                )
            )
        case .conversational:
            await ToastScheduler.shared.schedule(
                toastType: .success(
                    deliveryType.symbol,
                    "Will attempt to notify all members of this conversation."
                )
            )
        case .respectful:
            break
        }
    }
}
