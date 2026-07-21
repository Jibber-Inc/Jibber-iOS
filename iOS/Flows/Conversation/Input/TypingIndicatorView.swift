//
//  TypingIndicatorView.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/30/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

/// Production binding for the shared presentation-only conversation indicator.
/// Parse/Combine stay app-only while the rendered view is also available to the
/// App Clip and onboarding.
class TypingIndicatorView: ConversationTypingIndicatorView {
    var subscriptions = Set<AnyCancellable>()
    
    var controller: ParseConversationController?
    
    override func initializeSubviews() {
        super.initializeSubviews()

        ConversationsManager.shared.$activeConversation.mainSink { conversation in
            if let cid = conversation?.id {
                self.subscribeToUpdates(for: cid)
            } else {
                self.subscriptions.removeAll()
                self.controller = nil
                self.hideText()
            }
        }.store(in: &self.cancellables)
    }
    
    private func subscribeToUpdates(for conversationId: String) {
        guard self.controller?.conversationID.rawValue != conversationId else { return }
        
        self.subscriptions.removeAll()
        
        self.controller = ParseConversationController.controller(for: conversationId)
        
        self.controller?.typingPeoplePublisher
            .mainSink(receiveValue: { [unowned self] typingUsers in
                self.showTyping(for: Array(typingUsers))
            }).store(in: &self.subscriptions)
    }
    
    func showTyping(for people: [PersonType]) {
        let typers = people.filter { person in
            return !person.isCurrentUser
        }
        
        guard typers.count > 0 else {
            // If no one is typying, hide
            self.hideText()
            return
        }
        
        var text = ""
        var names: [String] = []
        
        for (index, person) in typers.enumerated() {
            if index == 0 {
                text.append(person.givenName)
            } else {
                text.append(", \(person.givenName)")
            }
            
            names.append(person.givenName)
        }
        
        text.append(" is typing...")
        
        self.setText(text, highlights: names, animated: true)
    }
}
