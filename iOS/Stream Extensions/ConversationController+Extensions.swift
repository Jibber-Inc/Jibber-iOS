//
//  ChatChannel+Async.swift
//  ChatChannel+Async
//
//  Created by Martin Young on 9/14/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat
import Intents
import Combine

typealias ConversationController = ChatChannelController

extension ConversationController {

    var conversation: Conversation? {
        return self.channel
    }
    
    static func controller(query: ChannelListQuery) -> ChatChannelListController {
        return JibberChatClient.shared.conversationController(query: query)!
    }
    
    static func controller(for conversation: Conversation) -> ConversationController {
        return JibberChatClient.shared.conversationController(for: conversation.id)!
    }
    
    static func controller(for conversationId: String) -> ConversationController {
        return JibberChatClient.shared.conversationController(for: conversationId)!
    }

    static func controller(for conversationId: String,
                           query: ChannelListQuery? = nil,
                           messageOrdering: MessageOrdering = .topToBottom) -> ConversationController {
        return JibberChatClient.shared.conversationController(for: conversationId,
                                                                 query: query,
                                                                 messageOrdering: messageOrdering)!
    }
    
    static func controller(for query: ChannelQuery,
                           messageOrdering: MessageOrdering = .topToBottom) -> ConversationController {
        return JibberChatClient.shared.conversationController(for: query,
                                                                 messageOrdering: messageOrdering)!
    }

    func getOldestUnreadMessage(withUserID userID: UserId) -> Message? {
        return self.conversation?.getOldestUnreadMessage(withUserID: userID)
    }

    /// Loads previous messages from backend including the one specified.
    /// - Parameters:
    ///   - messageId: ID of the last fetched message. You will get messages `older` and including the provided ID.
    ///   - limit: Limit for page size.
    func loadPreviousMessages(including messageId: MessageId, limit: Int = 25) async throws {
        guard let cid = self.cid else { return }
        try await self.loadPreviousMessages(before: messageId, limit: limit)
        guard let controller = MessageController.controller(for: cid.description, messageId: messageId) else { return }
        if let messageBefore = self.messages.first(where: { message in
            guard let msg = controller.message else { return false }
            return message.createdAt < msg.createdAt
        }) {
            try await self.loadNextMessages(after: messageBefore.id, limit: 1)
        }
    }

    /// Loads previous messages from backend.
    /// - Parameters:
    ///   - messageId: ID of the last fetched message. You will get messages `older` than the provided ID.
    ///   - limit: Limit for page size.
    func loadPreviousMessages(before messageId: MessageId? = nil, limit: Int = 25) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.loadPreviousMessages(before: messageId, limit: limit) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Loads next messages from backend including the one specified.
    ///
    /// - Parameters:
    ///   - messageId: ID of the message we want to load. You will also get messages `newer` than the provided ID.
    ///   - limit: Limit for page size.
    func loadNextMessages(including messageId: MessageId, limit: Int = 25) async throws {
        try await self.loadNextMessages(after: messageId, limit: limit)

        // If we haven't loaded the specified message,
        // then it's the next message in the list so load one more.
        guard !self.messages.contains(where: { message in
            message.id == messageId
        }) else { return }

        try await self.loadPreviousMessages(limit: 1)
    }

    /// Loads next messages from backend.
    ///
    /// - Parameters:
    ///   - messageId: ID of the current first message. You will get messages `newer` than the provided ID.
    ///   - limit: Limit for page size.
    func loadNextMessages(after messageId: MessageId? = nil, limit: Int = 25) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.loadNextMessages(after: messageId, limit: limit) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Returns the most recently sent message from either the current user or from another user.
    func getMostRecentMessage(fromCurrentUser: Bool) -> Message? {
        let allMessages: [Message] = Array(self.messages)

        // Find the most recent message that was sent by the user.
        return allMessages.first { message in
            if fromCurrentUser {
                return message.isFromCurrentUser
            } else {
                return !message.isFromCurrentUser
            }
        }
    }

    func donateIntent(for sendable: Sendable) async {
        guard case MessageKind.text(let text) = sendable.kind else { return }
        let memberIDs = self.conversation?.lastActiveMembers.compactMap { member in
            return member.personId
        } ?? []

        let recipients = PeopleStore.shared.usersArray.filter { user in
            return memberIDs.contains(user.objectId ?? String())
        }.compactMap { user in
            return user.iNPerson
        }

        let sender = recipients.first { inperson in
            return inperson.isMe
        }

        let intent = INSendMessageIntent(recipients: recipients,
                                         outgoingMessageType: .outgoingMessageText,
                                         content: text,
                                         speakableGroupName: self.conversation?.speakableGroupName,
                                         conversationIdentifier: self.conversation?.cid.id,
                                         serviceName: nil,
                                         sender: sender,
                                         attachments: nil)

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        try? await interaction.donate()
    }

    @discardableResult
    func createNewMessage(with sendable: Sendable) async throws -> MessageId {
        let messageBody: String
        var attachments: [AnyAttachmentPayload] = []
        var extraData: [String: RawJSON] = [:]

        switch sendable.kind {
        case .text(let text):
            messageBody = text
        case .photo(let item, let body):
            if let url = item.url {
                let attachment = try AnyAttachmentPayload(localFileURL: url,
                                                          attachmentType: .image,
                                                          extraData: nil)
                attachments.append(attachment)
            }
            messageBody = body
        case .video(video: let item, let body):
            
            if let url = item.url {
                let previewID = UUID().uuidString
                var videoData: [String: RawJSON] = [:]
                videoData["previewID"] = .string(previewID)
            
                let attachment = try AnyAttachmentPayload(localFileURL: url, attachmentType: .video, extraData: videoData)
                attachments.append(attachment)
                
                if let previewURL = item.previewURL {
                    let previewAttachment = try AnyAttachmentPayload(localFileURL: previewURL,
                                                                     attachmentType: .image,
                                                                     extraData: videoData)
                    attachments.append(previewAttachment)
                }
            }
            messageBody = body
        case .media(items: let media, body: let body):
            media.forEach { item in
                switch item.type {
                case .photo:
                    if let url = item.url, let attachment = try? AnyAttachmentPayload(localFileURL: url,
                                                                                      attachmentType: .image,
                                                                                      extraData: nil) {
                        
                        attachments.append(attachment)
                    }
                case .video:
                    if let url = item.url {
                        let previewID = UUID().uuidString
                        var videoData: [String: RawJSON] = [:]
                        videoData["previewID"] = .string(previewID)
                    
                        if let attachment = try? AnyAttachmentPayload(localFileURL: url,
                                                                      attachmentType: .video,
                                                                      extraData: videoData) {
                            attachments.append(attachment)
                        }
                        
                        if let previewURL = item.previewURL,
                            let previewAttachment = try? AnyAttachmentPayload(localFileURL: previewURL,
                                                                              attachmentType: .image,
                                                                              extraData: videoData) {
                            
                            attachments.append(previewAttachment)
                        }
                    }
                }
            }
            messageBody = body
            
        case .link(_, let stringURL):
            // The link URL is automatically detected by stream and added as an attachment.
            // Removing extra whitespace and make links lower case.
            messageBody = stringURL.trimWhitespace().lowercased()
        case .attributedText, .location, .emoji, .audio, .contact:
            throw(ClientError.apiError(detail: "Message type not supported."))
        }
        
        if let expression = sendable.expression {
            let expressionDict: [String: RawJSON] = ["authorId": .string(User.current()!.objectId!),
                                                     "expressionId": .string(expression.objectId!)]
            
            extraData = ["expressions" : .array([.dictionary(expressionDict)])]
            
            AchievementsManager.shared.createIfNeeded(with: .firstExpression)
        }

        return try await self.createNewMessage(sendable: sendable,
                                               text: messageBody,
                                               attachments: attachments,
                                               extraData: extraData)
    }

    /// Creates a new message locally and schedules it for send.
    ///
    /// - Parameters:
    ///   - text: Text of the message.
    ///   - pinning: Pins the new message. `nil` if should not be pinned.
    ///   - isSilent: A flag indicating whether the message is a silent message.
    ///     Silent messages are special messages that don't increase the unread messages count nor mark a channel as unread.
    ///   - attachments: An array of the attachments for the message.
    ///     `Note`: can be built-in types, custom attachment types conforming to `AttachmentEnvelope` protocol
    ///     and `ChatMessageAttachmentSeed`s.
    ///   - quotedMessageId: An id of the message new message quotes. (inline reply)
    ///   - extraData: Additional extra data of the message object.
    @discardableResult
    func createNewMessage(sendable: Sendable,
                          text: String,
                          pinning: MessagePinning? = nil,
                          isSilent: Bool = false,
                          attachments: [AnyAttachmentPayload] = [],
                          mentionedUserIds: [UserId] = [],
                          quotedMessageId: MessageId? = nil,
                          extraData: [String: RawJSON] = [:]) async throws -> MessageId {

        return try await withCheckedThrowingContinuation { continuation in
            var data = extraData
            data["context"] = .string(sendable.deliveryType.rawValue)
            self.createNewMessage(text: text,
                                  pinning: pinning,
                                  isSilent: isSilent,
                                  attachments: attachments,
                                  mentionedUserIds: mentionedUserIds,
                                  quotedMessageId: quotedMessageId,
                                  extraData: data) { result in

                switch result {
                case .success(let messageID):
                    logDebug(messageID)
                    continuation.resume(returning: messageID)

                    Task {
                        await self.donateIntent(for: sendable)
                        await self.presentToast(for: sendable, messageId: messageID)
                    }
                    AchievementsManager.shared.createIfNeeded(with: .firstMessage)
                    AnalyticsManager.shared.trackEvent(type: .messageSent, properties: nil)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func presentToast(for sendable: Sendable, messageId: String) async {
        
        switch sendable.deliveryType {
        case .timeSensitive:
            await ToastScheduler.shared
                .schedule(toastType: .success(sendable.deliveryType.symbol,
                                              "Will notify all members of this conversation."))
            
        case .conversational:
            await ToastScheduler.shared
                .schedule(toastType: .success(sendable.deliveryType.symbol,
                                              "Will attempt to notify all members of this conversation."))
        
        case .respectful:
            break
        }
    }

    func editMessage(with sendable: Sendable) async throws {
        guard let messageID = sendable.previousMessage?.id else {
            throw(ClientError.apiError(detail: "No message id"))
        }

        switch sendable.kind {
        case .text(let text):
            return try await self.editMessage(sendable: sendable,
                                              messageID: messageID,
                                              text: text)
        case .attributedText:
            break
        case .photo:
            break
        case .video:
            break
        case .location:
            break
        case .emoji:
            break
        case .audio:
            break
        case .contact:
            break
        case .link:
            break
        case .media:
            break 
        }

        throw(ClientError.apiError(detail: "Message type not supported."))
    }

    /// Edits the specified message contained in this controller's channel with the provided value.
    ///
    /// - Parameters:
    ///   - text: The updated message text.
    func editMessage(sendable: Sendable,
                     messageID: MessageId,
                     text: String) async throws {

        guard let channelID = self.cid else {
            throw(ClientError.apiError(detail: "No channel id"))
        }

        let messageController = self.client.messageController(cid: channelID, messageId: messageID)
        return try await withCheckedThrowingContinuation({ continuation in
            messageController.editMessage(text: text) { error in
                if let e = error {
                    continuation.resume(throwing: e)
                } else {
                    Task {
                        await self.donateIntent(for: sendable)
                    }
                    continuation.resume(returning: ())
                }
            }
        })
    }

    /// Creates a new reply message locally and schedules it for send.
    ///
    /// - Parameters:
    ///   - messageID: The id of the message we're replying to.
    ///   - text: Text of the message.
    ///   - pinning: Pins the new message. `nil` if should not be pinned.
    ///   - attachments: An array of the attachments for the message.
    ///    `Note`: can be built-in types, custom attachment types conforming to `AttachmentEnvelope` protocol
    ///     and `ChatMessageAttachmentSeed`s.
    ///   - showReplyInChannel: Set this flag to `true` if you want the message to be also visible in the channel, not only
    ///   in the response thread.
    ///   - quotedMessageId: An id of the message new message quotes. (inline reply)
    ///   - extraData: Additional extra data of the message object.
    ///   - completion: Called when saving the message to the local DB finishes.
    @discardableResult
    func createNewReply(sendable: Sendable,
                        messageID: MessageId,
                        text: String,
                        pinning: MessagePinning? = nil,
                        attachments: [AnyAttachmentPayload] = [],
                        mentionedUserIds: [UserId] = [],
                        showReplyInChannel: Bool = false,
                        isSilent: Bool = false,
                        quotedMessageId: MessageId? = nil,
                        extraData: [String: RawJSON] = [:]) async throws -> MessageId {

        guard let channelID = self.cid else {
            throw(ClientError.apiError(detail: "No channel id"))
        }

        let messageController = self.client.messageController(cid: channelID, messageId: messageID)

        return try await withCheckedThrowingContinuation({ continuation in
            var data = extraData
            data["context"] = .string(sendable.deliveryType.rawValue)
            messageController.createNewReply(text: text,
                                             pinning: pinning,
                                             attachments: attachments,
                                             mentionedUserIds: mentionedUserIds,
                                             showReplyInChannel: showReplyInChannel,
                                             isSilent: isSilent,
                                             quotedMessageId: quotedMessageId,
                                             extraData: data) { result in
                switch result {
                case .success(let messageId):
                    continuation.resume(returning: messageId)
                    Task {
                        await self.donateIntent(for: sendable)
                    }
                    AchievementsManager.shared.createIfNeeded(with: .firstReply)
                    AnalyticsManager.shared.trackEvent(type: .replySent, properties: nil)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        })
    }

    /// Deletes the specified message that this controller manages.
    ///
    /// - Parameters:
    ///   - messageID: The id of the message to be deleted.
    func deleteMessage(_ messageID: MessageId) async throws {
        guard let channelID = self.cid else {
            throw(ClientError.apiError(detail: "No channel id"))
        }

        let messageController = self.client.messageController(cid: channelID, messageId: messageID)
        try await messageController.deleteMessage()
    }

    /// Deletes the specified message that this controller manages.
    ///
    /// - Parameters:
    ///   - messageID: The id of the message to be deleted.
    ///   - completion: The completion. Will be called on a **callbackQueue** when the network request is finished.
    ///                 If request fails, the completion will be called with an error.
    func deleteMessage(_ messageID: MessageId, completion: ((Error?) -> Void)? = nil) {
        guard let channelID = self.cid else {
            completion?(ClientError.apiError(detail: "No channel id"))
            return
        }

        let messageController = self.client.messageController(cid: channelID, messageId: messageID)
        messageController.deleteMessage(hard: true, completion: completion)
    }

    /// Delete the channel this controller manages.
    func deleteChannel() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.deleteChannel { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Remove users to the channel as members.
    ///
    /// - Parameters:
    ///   - users: Users Id to remove from conversation.
    func removeMembers(userIds: Set<UserId>) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.removeMembers(userIds: userIds) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Hide the channel this controller manages from queryChannels for the user until a message is added.
    ///
    /// - Parameters:
    ///   - clearHistory: Flag to remove channel history (**false** by default)
    func hideChannel(clearHistory: Bool = false) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.hideChannel(clearHistory: clearHistory) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Removes hidden status for the channel this controller manages.
    func showChannel() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.showChannel { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Marks the channel as read.
    func markRead() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.markRead { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

extension ConversationController: MessageSequenceController {
    
    var memberCount: Int {
        return self.conversation?.memberCount ?? 0 
    }

    var conversationId: String? {
        return self.cid?.description
    }

    var messageSequence: MessageSequence? {
        return self.conversation
    }

    var messageArray: [Messageable] {
        return Array(self.messages)
    }

    var messageSequenceChangePublisher: AnyPublisher<EntityChange<MessageSequence>, Never> {
        return self.channelChangePublisher.map { messageChange in
            let change: EntityChange<MessageSequence>

            switch messageChange {
            case .create(let conversation):
                change = EntityChange.create(conversation)
            case .update(let conversation):
                change = EntityChange.update(conversation)
            case .remove(let conversation):
                change = EntityChange.remove(conversation)
            }

            return change
        }.eraseToAnyPublisher()
    }
    
    func add(expression: Expression) async throws {
        
        var extraData = self.conversation?.extraData ?? [:]
        var expressions: [RawJSON] = []
        if let value = extraData["expressions"], case RawJSON.array(let array) = value {
            expressions = array
        }
        do {
            let saved = try await expression.saveToServer()
            
            let expressionDict: [String: RawJSON] = ["authorId": .string(User.current()!.objectId!),
                                                     "expressionId": .string(saved.objectId!)]
            expressions.append(.dictionary(expressionDict))
            
            extraData["expressions"] = .array(expressions)
        } catch {
            throw(ClientError.apiError(detail: "Error saving expression for message."))
        }
        
        return await withCheckedContinuation({ continuation in
            self.updateChannel(name: nil, imageURL: nil, team: nil, extraData: extraData) { error in
                if let e = error {
                    Task {
                        await ToastScheduler.shared.schedule(toastType: .error(e))
                    }
                    logError(e)
                } else {
                    Task {
                        await ToastScheduler.shared.schedule(toastType: .success(ImageSymbol.faceSmiling, "Expression added"))
                    }
                }
                continuation.resume(returning: ())
            }
        })
    }
}
