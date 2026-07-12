//
//  MessageSequence.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/17/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

protocol MessageSequence {

    var id: String { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var isCreatedByCurrentUser: Bool { get }
    var authorId: String { get }
    var attributes: [String: Any]? { get }
    var messages: [Messageable] { get }
    var title: String? { get }
    var totalUnread: Int { get }
}

func ==(lhs: MessageSequence, rhs: MessageSequence) -> Bool {
    guard type(of: lhs) == type(of: rhs) else { return false }
    return lhs.id == rhs.id
        && lhs.createdAt == rhs.createdAt
        && lhs.updatedAt == rhs.updatedAt
        && lhs.authorId == rhs.authorId
}

extension MessageSequence {

    var isCreatedByCurrentUser: Bool {
        guard let user = User.current() else { return false }
        return user.objectId == self.authorId
    }
    
    var totalUnread: Int {
        var total: Int = 0
        self.messages.forEach { message in
            if !message.isFromCurrentUser, !message.isConsumedByMe, !message.isDeleted {
                total += 1
            }
        }
        
        return total
    }
}
