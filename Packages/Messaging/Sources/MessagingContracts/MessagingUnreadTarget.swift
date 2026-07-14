//
//  MessagingUnreadTarget.swift
//  MessagingContracts
//

public enum MessagingUnreadTargetResolution: Equatable, Sendable {
    case target(MessagingMessageID)
    case needsOlderPage
    case none
}

public enum MessagingUnreadCandidateResolution: Equatable, Sendable {
    case target(MessagingUnreadTargetCandidate)
    case needsOlderPage
    case none
}

/// An unread timeline item and the root message that can represent it in the
/// conversation UI. For root messages both identifiers are the same. Replies
/// use their own identifier for unread ordering and their parent's identifier
/// as the visible target.
public struct MessagingUnreadTargetCandidate: Equatable, Sendable {
    public let unreadMessageID: MessagingMessageID
    public let visibleRootMessageID: MessagingMessageID

    public init(
        unreadMessageID: MessagingMessageID,
        visibleRootMessageID: MessagingMessageID
    ) {
        self.unreadMessageID = unreadMessageID
        self.visibleRootMessageID = visibleRootMessageID
    }
}

/// Resolves the oldest unread message without mistaking a partial local page
/// for the start of the unread range.
public enum MessagingUnreadTargetResolver {
    /// Preserves both the unread timeline identity and its visible root. The UI
    /// needs the former to open/consume an unread reply and the latter to focus
    /// the root-only conversation collection before presenting the thread.
    public static func resolveCandidate(
        serverUnreadCount: Int,
        loadedUnreadCandidatesOldestFirst: [MessagingUnreadTargetCandidate],
        hasLoadedAll: Bool
    ) -> MessagingUnreadCandidateResolution {
        let resolution = self.resolve(
            serverUnreadCount: serverUnreadCount,
            loadedUnreadMessageIDsOldestFirst: loadedUnreadCandidatesOldestFirst.map(
                \.unreadMessageID
            ),
            hasLoadedAll: hasLoadedAll
        )
        switch resolution {
        case .needsOlderPage:
            return .needsOlderPage
        case .none:
            return .none
        case .target(let unreadMessageID):
            guard let candidate = loadedUnreadCandidatesOldestFirst.first(where: {
                $0.unreadMessageID == unreadMessageID
            }) else {
                return .none
            }
            return .target(candidate)
        }
    }

    /// - Parameters:
    ///   - serverUnreadCount: The authoritative unread count for the member.
    ///   - loadedUnreadMessageIDsOldestFirst: Unique unread IDs in ascending
    ///     timeline order from the history currently loaded on the device.
    ///   - hasLoadedAll: Whether no older message page remains.
    public static func resolve(
        serverUnreadCount: Int,
        loadedUnreadMessageIDsOldestFirst: [MessagingMessageID],
        hasLoadedAll: Bool
    ) -> MessagingUnreadTargetResolution {
        guard serverUnreadCount > 0 else { return .none }

        if loadedUnreadMessageIDsOldestFirst.count >= serverUnreadCount {
            // When local receipt state lags the authoritative count, discard
            // surplus candidates from the older edge of the loaded range.
            let targetIndex = loadedUnreadMessageIDsOldestFirst.count - serverUnreadCount
            return .target(loadedUnreadMessageIDsOldestFirst[targetIndex])
        }

        if !hasLoadedAll {
            return .needsOlderPage
        }

        // The server count can temporarily exceed locally resolvable messages
        // after deletion or filtering. Once all history is loaded, the oldest
        // available candidate is the best stable target.
        if let oldestLoadedUnread = loadedUnreadMessageIDsOldestFirst.first {
            return .target(oldestLoadedUnread)
        }

        return .none
    }
}
