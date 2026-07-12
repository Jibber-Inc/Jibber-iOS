//
//  Message+Extensions.swift
//  Jibber
//

import Foundation
import MessagingContracts
import ParseCore

typealias Message = ParseMessage

struct ParseReadReaction {
    let author: PersonType
    let createdAt: Date
}

extension Message {
    @MainActor
    var readReactions: [ParseReadReaction] {
        self.snapshot.receipts.compactMap { receipt in
            guard receipt.state == .read else { return nil }
            let person: PersonType?
            if receipt.userID == User.current()?.objectId {
                person = User.current()
            } else {
                person = PeopleStore.shared.usersArray.first { $0.objectId == receipt.userID }
            }
            guard let person else { return nil }
            return ParseReadReaction(author: person, createdAt: receipt.occurredAt)
        }
    }
}
