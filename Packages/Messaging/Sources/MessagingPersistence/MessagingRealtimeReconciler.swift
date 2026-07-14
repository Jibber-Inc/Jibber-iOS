//
//  MessagingRealtimeReconciler.swift
//  MessagingPersistence
//

import Foundation
import MessagingContracts

public enum MessagingReconciliationDecision: Hashable {
    case upsert(MessagingMessageSnapshot)
    case ignore
}

public enum MessagingMessageReconciler {
    /// Reconciles the independently versioned message core and related state.
    /// A server-confirmed copy always confirms an optimistic copy with the same
    /// client-generated ID, while an older page can contribute only related
    /// records that are themselves newer than the cached records.
    public static func reconcile(
        local: MessagingMessageSnapshot?,
        remote: MessagingMessageSnapshot
    ) -> MessagingReconciliationDecision {
        guard let local = local else { return .upsert(remote) }

        var aggregate: MessagingMessageSnapshot
        if local.objectID == nil, remote.objectID != nil {
            aggregate = remote
        } else if isRemoteCoreOlder(than: local, remote: remote) {
            aggregate = local
        } else {
            aggregate = remote
        }

        aggregate.reactions = mergedReactions(
            preserving: local.reactions,
            including: remote.reactions
        )
        aggregate.receipts = mergedReceipts(
            preserving: local.receipts,
            including: remote.receipts
        )

        // Confirmation is local transport state, not part of server core
        // freshness. A delayed confirmation may not revert a newer edit, but
        // it must still finish the optimistic send.
        if remote.objectID != nil, remote.localState == .confirmed {
            aggregate.localState = .confirmed
            aggregate.lastFailureDescription = nil
        }

        return local == aggregate ? .ignore : .upsert(aggregate)
    }

    private static func isRemoteCoreOlder(
        than local: MessagingMessageSnapshot,
        remote: MessagingMessageSnapshot
    ) -> Bool {
        switch (local.serverUpdatedAt, remote.serverUpdatedAt) {
        case let (localUpdated?, remoteUpdated?):
            return remoteUpdated < localUpdated
        case (_?, nil):
            return true
        case (nil, _):
            return false
        }
    }

    static func apply(
        _ reaction: MessagingReactionSnapshot,
        to reactions: inout [MessagingReactionSnapshot]
    ) {
        guard let index = reactions.firstIndex(where: {
            if let objectID = reaction.objectID, $0.objectID == objectID { return true }
            return $0.userID == reaction.userID && $0.type == reaction.type
        }) else {
            // Keep deletion tombstones. Without one, a stale hydrated page that
            // excludes deleted reactions can resurrect an older active value.
            reactions.append(reaction)
            return
        }
        guard shouldReplace(reactions[index], with: reaction) else { return }
        reactions[index] = reaction
    }

    static func apply(
        _ receipt: MessagingReceiptSnapshot,
        to receipts: inout [MessagingReceiptSnapshot]
    ) {
        guard let index = receipts.firstIndex(where: { $0.userID == receipt.userID }) else {
            receipts.append(receipt)
            return
        }
        guard shouldReplace(receipts[index], with: receipt) else { return }
        receipts[index] = receipt
    }

    static func mergedReactions(
        preserving local: [MessagingReactionSnapshot],
        including remote: [MessagingReactionSnapshot]
    ) -> [MessagingReactionSnapshot] {
        var result = local
        for reaction in remote { apply(reaction, to: &result) }
        return result
    }

    static func mergedReceipts(
        preserving local: [MessagingReceiptSnapshot],
        including remote: [MessagingReceiptSnapshot]
    ) -> [MessagingReceiptSnapshot] {
        var result = local
        for receipt in remote { apply(receipt, to: &result) }
        return result
    }

    private static func shouldReplace(
        _ existing: MessagingReactionSnapshot,
        with incoming: MessagingReactionSnapshot
    ) -> Bool {
        // A contradictory LiveQuery event or hydrated page may have been sent
        // before the user's durable mutation. Keep the optimistic value until
        // Parse returns the requested active/tombstoned state. The matching
        // authoritative value then replaces it and clears all local markers.
        if let localState = existing.localMutationState,
           incoming.localMutationState == nil {
            return incoming.type == existing.type
                && incoming.isActive == localState.intendsSelection
        }
        switch (existing.serverUpdatedAt, incoming.serverUpdatedAt) {
        case let (existingUpdated?, incomingUpdated?):
            if incomingUpdated != existingUpdated {
                return incomingUpdated > existingUpdated
            }
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case (nil, nil):
            let existingDate = existing.deletedAt ?? existing.createdAt
            let incomingDate = incoming.deletedAt ?? incoming.createdAt
            if incomingDate != existingDate { return incomingDate > existingDate }
        }
        // A deletion is the safe deterministic result for tied versions.
        return incoming.isDeleted && !existing.isDeleted
    }

    private static func shouldReplace(
        _ existing: MessagingReceiptSnapshot,
        with incoming: MessagingReceiptSnapshot
    ) -> Bool {
        switch (existing.serverUpdatedAt, incoming.serverUpdatedAt) {
        case let (existingUpdated?, incomingUpdated?):
            if incomingUpdated != existingUpdated {
                return incomingUpdated > existingUpdated
            }
            return false
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case (nil, nil):
            if incoming.occurredAt != existing.occurredAt {
                return incoming.occurredAt > existing.occurredAt
            }
            return false
        }
    }
}

/// Tracks whether a completed LiveQuery subscription recovery must be followed
/// by one authoritative refresh. Consuming the flag before replacing the
/// subscription prevents the replacement's own `.connected` event from
/// starting a refresh loop.
public struct MessagingRealtimeCatchUpTracker: Hashable {
    public private(set) var isCatchUpRequired = false

    public init() {}

    public mutating func disconnected() {
        isCatchUpRequired = true
    }

    public mutating func consumeCatchUpOnConnected() -> Bool {
        guard isCatchUpRequired else { return false }
        isCatchUpRequired = false
        return true
    }
}

/// Applies LiveQuery events to the durable store. Event delivery can be
/// duplicated or out of order; reconciliation makes application idempotent.
public final class MessagingRealtimeReconciler {
    private static let maximumPendingMessageCount = 500
    private let store: MessagingLocalStore
    private var pendingReactions: [MessagingMessageID: [MessagingReactionSnapshot]] = [:]
    private var pendingReceipts: [MessagingMessageID: [MessagingReceiptSnapshot]] = [:]

    public init(store: MessagingLocalStore) {
        self.store = store
    }

    public func apply(_ event: MessagingRealtimeEvent) throws {
        switch event {
        case .connected, .disconnected, .conversationSetInvalidated:
            break
        case .conversationUpserted(let conversation):
            try store.upsert(conversations: [conversation])
        case .memberUpserted(let member):
            try store.upsert(members: [member])
        case .messageUpserted(let message):
            try reconcile(message)
        case .messageDeleted(var message):
            message.isDeleted = true
            try reconcile(message)
        case .reactionUpserted(let reaction):
            try apply(reaction)
        case .receiptUpserted(let receipt):
            try apply(receipt)
        }
    }

    private func reconcile(_ remote: MessagingMessageSnapshot) throws {
        let local = try remote.objectID.flatMap { try store.cachedMessage(objectID: $0) }
            ?? store.cachedMessage(clientMessageID: remote.clientMessageID)
        var aggregate = remote
        if let local = local {
            aggregate.reactions = MessagingMessageReconciler.mergedReactions(
                preserving: local.reactions,
                including: aggregate.reactions
            )
            aggregate.receipts = MessagingMessageReconciler.mergedReceipts(
                preserving: local.receipts,
                including: aggregate.receipts
            )
        }
        if let messageID = aggregate.objectID {
            for reaction in pendingReactions.removeValue(forKey: messageID) ?? [] {
                Self.apply(reaction, to: &aggregate)
            }
            for receipt in pendingReceipts.removeValue(forKey: messageID) ?? [] {
                Self.apply(receipt, to: &aggregate)
            }
        }
        // GRDB performs the final read/compare/write atomically. Do not make a
        // non-atomic ignore decision from the snapshot read above.
        try store.upsert(messages: [aggregate])
    }

    private func apply(_ reaction: MessagingReactionSnapshot) throws {
        guard var message = try store.cachedMessage(objectID: reaction.messageID) else {
            prunePendingEventsIfNeeded(forNewMessageID: reaction.messageID)
            var values = pendingReactions[reaction.messageID] ?? []
            Self.apply(reaction, to: &values)
            pendingReactions[reaction.messageID] = values
            return
        }
        Self.apply(reaction, to: &message)
        try store.upsert(messages: [message])
    }

    private func apply(_ receipt: MessagingReceiptSnapshot) throws {
        guard var message = try store.cachedMessage(objectID: receipt.messageID) else {
            prunePendingEventsIfNeeded(forNewMessageID: receipt.messageID)
            var values = pendingReceipts[receipt.messageID] ?? []
            Self.apply(receipt, to: &values)
            pendingReceipts[receipt.messageID] = values
            return
        }
        Self.apply(receipt, to: &message)
        try store.upsert(messages: [message])
    }

    private func prunePendingEventsIfNeeded(
        forNewMessageID messageID: MessagingMessageID
    ) {
        let knownIDs = Set(pendingReactions.keys).union(pendingReceipts.keys)
        guard !knownIDs.contains(messageID),
              knownIDs.count >= Self.maximumPendingMessageCount,
              let evictionCandidate = knownIDs.first else { return }
        pendingReactions[evictionCandidate] = nil
        pendingReceipts[evictionCandidate] = nil
    }

    private static func apply(
        _ reaction: MessagingReactionSnapshot,
        to message: inout MessagingMessageSnapshot
    ) {
        apply(reaction, to: &message.reactions)
    }

    private static func apply(
        _ reaction: MessagingReactionSnapshot,
        to reactions: inout [MessagingReactionSnapshot]
    ) {
        MessagingMessageReconciler.apply(reaction, to: &reactions)
    }

    private static func apply(
        _ receipt: MessagingReceiptSnapshot,
        to message: inout MessagingMessageSnapshot
    ) {
        apply(receipt, to: &message.receipts)
    }

    private static func apply(
        _ receipt: MessagingReceiptSnapshot,
        to receipts: inout [MessagingReceiptSnapshot]
    ) {
        MessagingMessageReconciler.apply(receipt, to: &receipts)
    }
}
