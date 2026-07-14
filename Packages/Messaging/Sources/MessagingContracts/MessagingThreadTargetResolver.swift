//
//  MessagingThreadTargetResolver.swift
//  MessagingContracts
//

public enum MessagingThreadTargetResolution: Equatable, Sendable {
    case rootMessageID(MessagingMessageID)
    case targetNotFound
    case nestedReply(parentMessageID: MessagingMessageID)
}

public enum MessagingThreadTargetResolver {

    /// Resolves a message selected for reply to Parse's one-level thread root.
    /// A missing parent is still a valid result because `replyToMessageID` is a
    /// server pointer and the root may simply be outside the caller's page.
    public static func resolve(
        messageID: MessagingMessageID,
        in messages: [MessagingMessageSnapshot]
    ) -> MessagingThreadTargetResolution {
        guard let target = messages.first(where: {
            $0.stableID == messageID || $0.objectID == messageID
        }) else {
            return .targetNotFound
        }

        guard let parentMessageID = target.replyToMessageID else {
            return .rootMessageID(target.canonicalMessageID)
        }

        if let parent = messages.first(where: {
            $0.stableID == parentMessageID || $0.objectID == parentMessageID
        }), parent.replyToMessageID != nil {
            return .nestedReply(parentMessageID: parent.canonicalMessageID)
        }

        return .rootMessageID(parentMessageID)
    }
}
