//
//  Conversation+Intents.swift
//  Jibber
//

import Foundation
import Intents

typealias Conversation = ParseConversation
typealias ConversationId = ParseConversationID

extension Conversation {
    var speakableGroupName: INSpeakableString? {
        guard let title, !title.isEmpty else { return nil }
        return INSpeakableString(
            vocabularyIdentifier: "",
            spokenPhrase: title,
            pronunciationHint: nil
        )
    }
}
