//
//  ReactionType.swift
//  Jibber
//
//  Created by Benji Dodgson on 4/11/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import MessagingContracts

/// The product-level reaction type is owned by the provider-neutral messaging
/// contract. This alias keeps the historical Jibber name at presentation call
/// sites without leaking emoji into Parse's stable wire values.
typealias ReactionType = MessagingReactionType

extension MessagingReactionType {

    var emoji: String {
        switch self {
        case .like:
            return "👍"
        case .love:
            return "😍"
        case .dislike:
            return "👎"
        }
    }

    var displayName: String {
        switch self {
        case .like:
            return "Like"
        case .love:
            return "Love"
        case .dislike:
            return "Dislike"
        }
    }
}
