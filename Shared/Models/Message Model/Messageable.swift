//
//  Messageable.swift
//  Benji
//
//  Created by Benji Dodgson on 11/9/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import MessagingContracts
import ParseCore

enum DeliveryStatus {
    case sending
    case sent
    case reading
    case read
    case error
}

protocol Messageable {

    var id: String { get }
    var parentMessageId: String? { get }
    var conversationId: String { get }
    var createdAt: Date { get }
    var isFromCurrentUser: Bool { get }
    var authorId: String { get }
    var attributes: [String: Any]? { get }
    var person: PersonType? { get }
    var deliveryStatus: DeliveryStatus { get }
    var deliveryType: MessageDeliveryType { get }
    var canBeConsumed: Bool { get }
    var isConsumedByMe: Bool { get }
    var isConsumed: Bool { get }
    var isReply: Bool { get }
    var hasBeenConsumedBy: [PersonType] { get }
    var nonMeConsumers: [PersonType] { get }
    var color: ThemeColor { get }
    var kind: MessageKind { get }
    var isDeleted: Bool { get }
    var totalReplyCount: Int { get }
    var totalUnreadReplyCount: Int { get }
    var recentReplies: [Messageable] { get }
    var lastUpdatedAt: Date? { get }

    var reactionGroups: [MessagingReactionGroup] { get }
    var selectedReactionType: MessagingReactionType? { get }
    var expressions: [ExpressionInfo] { get }

    func setToConsumed() async
    func setToUnconsumed() async throws
    func appendAttributes(with attributes: [String: Any]) async throws -> Messageable
}

func ==(lhs: Messageable, rhs: Messageable) -> Bool {
    guard type(of: lhs) == type(of: rhs) else { return false }
    return lhs.createdAt == rhs.createdAt
        && lhs.kind == rhs.kind
        && lhs.authorId == rhs.authorId
        && lhs.id == rhs.id
        && lhs.parentMessageId == rhs.parentMessageId
        && lhs.conversationId == rhs.conversationId
}

extension Messageable {

    var reactionGroups: [MessagingReactionGroup] { [] }
    var selectedReactionType: MessagingReactionType? { nil }
    
    var parentMessageId: String? {
        return nil 
    }

    var canBeConsumed: Bool {
        return !self.isConsumedByMe && !self.isFromCurrentUser
    }

    var isConsumed: Bool {
        return self.hasBeenConsumedBy.count > 0 
    }

    var isConsumedByMe: Bool {
        return self.hasBeenConsumedBy.contains { person in
            return person.personId == User.current()?.objectId
        }
    }

    func appendAttributes(with attributes: [String: Any]) async throws -> Messageable {
        return self
    }

    var color: ThemeColor {
        if self.isFromCurrentUser {
            if self.deliveryType == .respectful {
                return .white
            } else {
                return self.deliveryType.color
            }
        } else {
            return .clear
        }
    }

    /// Returns the most recent reply to this message that is loaded or, if there are no replies, the message itself is returned.
    /// NOTE: If this message has not loaded its replies yet, the most recent reply will not be available and nil will be returned.
    var mostRecentMessage: Messageable? {
        if self.totalReplyCount == 0 {
            return self
        }

        return self.recentReplies.first
    }
    
    var nonMeConsumers: [PersonType] {
        return self.hasBeenConsumedBy.filter { person in
            return !person.isCurrentUser
        }
    }
    
    var authorExpression: ExpressionInfo? {
        return self.expressions.first { info in
            return info.authorId == self.authorId
        }
    }
    
    var totalUnreadReplyCount: Int {
        var count: Int = 0
        self.recentReplies.forEach { reply in
            if reply.canBeConsumed {
                count += 1
            }
        }
        
        return count
    }

    var isReply: Bool {
        return self.parentMessageId.exists
    }
}
