//
//  MessagingReactions.swift
//  MessagingContracts
//
//  Typed, vendor-neutral reaction values used by presentation adapters.
//

import Foundation

/// The lightweight message reactions supported by the historical Jibber UI.
/// These raw values are persisted by Parse; emoji remain a presentation-layer
/// concern so the contracts target does not dictate visual styling.
public enum MessagingReactionType: String, Codable, CaseIterable, Hashable, Sendable {
    case like
    case love
    case dislike
}

/// Local state for an optimistic reaction mutation. A non-nil value means the
/// cached reaction is the user's requested state, not yet authoritative Parse
/// state. Failed values let presentation adapters avoid implying delivery.
public enum MessagingLocalReactionState: String, Codable, Hashable, Sendable {
    case selecting
    case removing
    case selectionFailed
    case removalFailed

    public var isPending: Bool {
        switch self {
        case .selecting, .removing:
            return true
        case .selectionFailed, .removalFailed:
            return false
        }
    }

    public var hasFailed: Bool { !isPending }

    public var intendsSelection: Bool {
        switch self {
        case .selecting, .selectionFailed:
            return true
        case .removing, .removalFailed:
            return false
        }
    }
}

/// One UI-ready aggregate for a supported reaction type.
public struct MessagingReactionGroup: Codable, Hashable, Identifiable, Sendable {
    public var type: MessagingReactionType
    public var userIDs: [MessagingUserID]
    public var isSelectedByCurrentUser: Bool
    public var currentUserMutationState: MessagingLocalReactionState?

    public init(
        type: MessagingReactionType,
        userIDs: [MessagingUserID],
        isSelectedByCurrentUser: Bool,
        currentUserMutationState: MessagingLocalReactionState? = nil
    ) {
        self.type = type
        self.userIDs = Array(Set(userIDs)).sorted()
        self.isSelectedByCurrentUser = isSelectedByCurrentUser
        self.currentUserMutationState = currentUserMutationState
    }

    public var id: MessagingReactionType { type }
    public var count: Int { userIDs.count }
}

/// One step in Jibber's historical unique-reaction behavior. Parse owns one
/// reaction row per message/user, so changing type is a single atomic select.
public struct MessagingReactionSelectionChange: Codable, Hashable, Sendable {
    public var type: MessagingReactionType
    public var isSelected: Bool

    public init(type: MessagingReactionType, isSelected: Bool) {
        self.type = type
        self.isSelected = isSelected
    }
}

public extension MessagingReactionSnapshot {
    /// Strictly maps persisted stable names to the supported reaction set.
    var reactionType: MessagingReactionType? { MessagingReactionType(rawValue: type) }

    /// Tombstones are retained for reconciliation but never presented as an
    /// active reaction.
    var isActive: Bool { !isDeleted && deletedAt == nil }
}

public extension MessagingMessageSnapshot {
    /// Active records of any type. Unknown future types remain available to a
    /// newer adapter without becoming one of this client's supported groups.
    var activeReactions: [MessagingReactionSnapshot] {
        reactions.filter(\.isActive)
    }

    /// Supported active reactions grouped in the stable product order. Counts
    /// are unique users so duplicate hydrated rows cannot inflate the UI.
    func reactionGroups(
        currentUserID: MessagingUserID
    ) -> [MessagingReactionGroup] {
        MessagingReactionType.allCases.compactMap { type in
            let active = activeReactions.filter { $0.reactionType == type }
            let userIDs = Array(Set(active.map(\.userID))).sorted()
            guard !userIDs.isEmpty else { return nil }
            return MessagingReactionGroup(
                type: type,
                userIDs: userIDs,
                isSelectedByCurrentUser: userIDs.contains(currentUserID),
                currentUserMutationState: reactionMutationState(
                    type: type,
                    for: currentUserID
                )
            )
        }
    }

    /// Returns the first selected type in stable product order. The backend's
    /// unique index normally leaves one row per user/type; deterministic order
    /// also makes legacy multi-selection data safe to present.
    func selectedReactionType(
        for userID: MessagingUserID
    ) -> MessagingReactionType? {
        MessagingReactionType.allCases.first { type in
            activeReactions.contains {
                $0.userID == userID && $0.reactionType == type
            }
        }
    }

    func reactionMutationState(
        type: MessagingReactionType,
        for userID: MessagingUserID
    ) -> MessagingLocalReactionState? {
        reactions.first {
            $0.userID == userID && $0.reactionType == type
        }?.localMutationState
    }

    /// Returns the exact durable operation to retry when the visible reaction
    /// represents a terminal local failure.
    func failedReactionMutationID(
        type: MessagingReactionType,
        for userID: MessagingUserID
    ) -> String? {
        reactions.first {
            $0.userID == userID
                && $0.reactionType == type
                && $0.localMutationState?.hasFailed == true
        }?.localMutationID
    }

    /// Tapping the current reaction removes it. Tapping another reaction asks
    /// Parse to atomically change the type on the user's unique selection.
    func reactionSelectionChanges(
        toggling type: MessagingReactionType,
        for userID: MessagingUserID
    ) -> [MessagingReactionSelectionChange] {
        let isRemovingSelection = activeReactions.contains {
            $0.userID == userID && $0.reactionType == type
        }
        return [.init(type: type, isSelected: !isRemovingSelection)]
    }
}
