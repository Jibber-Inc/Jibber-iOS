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
    /// Server timestamps order confirmed updates. A server-confirmed copy always
    /// replaces an optimistic copy with the same client-generated ID.
    public static func reconcile(
        local: MessagingMessageSnapshot?,
        remote: MessagingMessageSnapshot
    ) -> MessagingReconciliationDecision {
        guard let local = local else { return .upsert(remote) }
        if local.objectID == nil, remote.objectID != nil {
            return .upsert(remote)
        }
        if let localUpdated = local.serverUpdatedAt,
           let remoteUpdated = remote.serverUpdatedAt,
           remoteUpdated < localUpdated {
            return .ignore
        }
        return local == remote ? .ignore : .upsert(remote)
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
            aggregate.reactions = Self.mergedReactions(
                preserving: local.reactions,
                including: aggregate.reactions
            )
            aggregate.receipts = Self.mergedReceipts(
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
        switch MessagingMessageReconciler.reconcile(local: local, remote: aggregate) {
        case .upsert(let message): try store.upsert(messages: [message])
        case .ignore: break
        }
    }

    private func apply(_ reaction: MessagingReactionSnapshot) throws {
        guard var message = try store.cachedMessage(objectID: reaction.messageID) else {
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
            var values = pendingReceipts[receipt.messageID] ?? []
            Self.apply(receipt, to: &values)
            pendingReceipts[receipt.messageID] = values
            return
        }
        Self.apply(receipt, to: &message)
        try store.upsert(messages: [message])
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
        reactions.removeAll {
            if let objectID = reaction.objectID, $0.objectID == objectID { return true }
            return $0.userID == reaction.userID && $0.type == reaction.type
        }
        if !reaction.isDeleted { reactions.append(reaction) }
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
        receipts.removeAll { $0.userID == receipt.userID }
        receipts.append(receipt)
    }

    private static func mergedReactions(
        preserving local: [MessagingReactionSnapshot],
        including remote: [MessagingReactionSnapshot]
    ) -> [MessagingReactionSnapshot] {
        var result = local
        for reaction in remote { apply(reaction, to: &result) }
        return result
    }

    private static func mergedReceipts(
        preserving local: [MessagingReceiptSnapshot],
        including remote: [MessagingReceiptSnapshot]
    ) -> [MessagingReceiptSnapshot] {
        var result = local
        for receipt in remote { apply(receipt, to: &result) }
        return result
    }
}
