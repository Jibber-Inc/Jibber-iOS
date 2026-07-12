//
//  MessagingIdempotencyKey.swift
//  MessagingContracts
//

import CryptoKit
import Foundation

public enum MessagingIdempotencyKey {
    /// Notification actions can be repeated by the OS, so their send ID must
    /// be deterministic. The authenticated actor is part of the identity: two
    /// members responding to the same notification are two distinct sends.
    public static func notificationReply(
        userID: MessagingUserID,
        conversationID: MessagingConversationID,
        messageID: MessagingMessageID,
        actionID: String
    ) -> String {
        let source = [userID, conversationID, messageID, actionID]
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "notification.reply.\(digest)"
    }
}
