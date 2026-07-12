//
//  SuggestedReply.swift
//  Jibber
//
//  Created by Benji Dodgson on 4/24/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

enum SuggestedReply: String, CaseIterable {
    
    case quickReply = "SUGGESTION_QUICK"
    case emoji = "SUGGESTION_EMOJI"
    case other = "SUGGESTION_OTHER"
    
    var text: String {
        switch self {
        case .quickReply:
            return "Quick Reply"
        case .emoji:
            return "Reaction"
        case .other:
            return "Add Reply"
        }
    }
    
    @MainActor
    var image: UIImage? {
        switch self {
        case .quickReply:
            return ImageSymbol.hare.image
        case .emoji:
            return ImageSymbol.thumbsUp.image
        case .other:
            return ImageSymbol.arrowTurnUpLeft.image
        }
    }
    
    var quickReplies: [String] {
        return ["I'm busy", "Great!", "Thanks", "What?", "On my way!", "Ok", "No thanks."]
    }
    
    var emojiReactions: [String] {
        return ["❤️", "👍", "👎", "😂", "😳", "🤨"]
    }
    
    var action: UNNotificationAction? {
        if self != .emoji {
            
            var icon: UNNotificationActionIcon? = nil
            
            switch self {
            case .quickReply:
                icon = UNNotificationActionIcon(systemImageName: "hare")
            case .emoji:
                icon = UNNotificationActionIcon(systemImageName: "hand.thumbsup")
            case .other:
                icon = UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left")
            }
            
            return UNNotificationAction(identifier: self.rawValue,
                                        title: self.text,
                                        options: .foreground,
                                        icon: icon)
        }
        
        return nil
    }
}
