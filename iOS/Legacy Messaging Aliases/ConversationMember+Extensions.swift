//
//  ConversationMember+Extensions.swift
//  Jibber
//

import Foundation

typealias ConversationMember = ParseConversationMember

extension Array where Element == ConversationMember {
    var userIDs: [String] {
        self.map(\.userID)
    }
}
