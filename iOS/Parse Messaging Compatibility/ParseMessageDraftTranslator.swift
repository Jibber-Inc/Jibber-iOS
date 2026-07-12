//
//  ParseMessageDraftTranslator.swift
//  Jibber
//

import Foundation
import MessagingContracts
import ParseCore

@MainActor
enum ParseMessageDraftTranslator {

    static func draft(
        from sendable: MessageSendable,
        conversationID: ParseConversationID,
        replyToMessageID: String? = nil,
        clientMessageID: String = UUID().uuidString.lowercased()
    ) async throws -> MessagingMessageDraft {
        guard !conversationID.rawValue.isEmpty else {
            throw ParseMessagingCompatibilityError.invalidConversationID
        }

        let content = try self.content(from: sendable.kind)
        var expressions: [MessagingExpressionReference] = []
        if let expression = sendable.expression {
            let saved = try await expression.saveToServer()
            guard let expressionID = saved.objectId,
                  let authorID = User.current()?.objectId else {
                throw ParseMessagingCompatibilityError.missingExpressionID
            }
            expressions.append(
                MessagingExpressionReference(authorID: authorID, expressionID: expressionID)
            )
        }

        let deliveryKind = MessagingDeliveryKind(rawValue: sendable.deliveryType.rawValue)
            ?? .respectful
        return MessagingMessageDraft(
            conversationID: conversationID.rawValue,
            clientMessageID: clientMessageID,
            content: content,
            replyToMessageID: replyToMessageID,
            deliveryKind: deliveryKind,
            expressions: expressions
        )
    }

    private static func content(from kind: MessageKind) throws -> MessagingMessageContent {
        switch kind {
        case .text(let text):
            return MessagingMessageContent(kind: .text, text: text)
        case .photo(let item, let body):
            return MessagingMessageContent(
                kind: .image,
                text: body,
                attachments: [try self.attachment(from: item)]
            )
        case .video(let item, let body):
            return MessagingMessageContent(
                kind: .video,
                text: body,
                attachments: [try self.attachment(from: item)]
            )
        case .media(let items, let body):
            return MessagingMessageContent(
                kind: .media,
                text: body,
                attachments: try items.map(self.attachment(from:))
            )
        case .link(let url, let stringURL):
            return MessagingMessageContent(
                kind: .link,
                text: stringURL.trimmingCharacters(in: .whitespacesAndNewlines),
                linkURL: url
            )
        case .attributedText:
            throw ParseMessagingCompatibilityError.unsupportedMessageKind("attributed-text")
        case .location:
            throw ParseMessagingCompatibilityError.unsupportedMessageKind("location")
        case .emoji:
            throw ParseMessagingCompatibilityError.unsupportedMessageKind("emoji")
        case .audio:
            throw ParseMessagingCompatibilityError.unsupportedMessageKind("audio")
        case .contact:
            throw ParseMessagingCompatibilityError.unsupportedMessageKind("contact")
        }
    }

    private static func attachment(from item: MediaItem) throws -> MessagingAttachmentSnapshot {
        guard let url = item.url else {
            throw ParseMessagingCompatibilityError.missingMediaURL
        }
        let localURL = url.isFileURL ? url : nil
        let remoteURL = url.isFileURL ? nil : url
        return MessagingAttachmentSnapshot(
            kind: item.type == .photo ? .image : .video,
            localURL: localURL,
            remoteURL: remoteURL,
            thumbnailURL: item.previewURL,
            fileName: item.fileName.isEmpty ? url.lastPathComponent : item.fileName,
            mimeType: item.type == .photo ? "image/jpeg" : "video/mp4",
            byteCount: item.data?.count,
            pixelWidth: item.size.width > 0 ? item.size.width : nil,
            pixelHeight: item.size.height > 0 ? item.size.height : nil
        )
    }
}
