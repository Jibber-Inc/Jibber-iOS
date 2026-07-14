import Foundation

/// Resolves a push that names a specific message into the root message the
/// conversation should load and, when applicable, the reply the thread should
/// reveal. This deliberately does not depend on the reply already being in a
/// local preview cache.
public struct MessagingNotificationRoute: Equatable, Sendable {
    public let messageID: String?
    public let threadRootMessageID: String?

    public init(messageID: String?, threadRootMessageID: String?) {
        self.messageID = messageID
        self.threadRootMessageID = threadRootMessageID
    }

    public var navigationMessageID: String? {
        guard let threadRootMessageID,
              threadRootMessageID != messageID else { return messageID }
        return threadRootMessageID
    }

    public var startingReplyMessageID: String? {
        guard let messageID,
              let threadRootMessageID,
              threadRootMessageID != messageID else { return nil }
        return messageID
    }

    public var isThreadReply: Bool {
        self.startingReplyMessageID != nil
    }
}
