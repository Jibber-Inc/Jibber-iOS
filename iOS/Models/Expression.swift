//
//  Expression.swift
//  Jibber
//
//  Created by Martin Young on 4/28/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

struct Expression {
    var imageURL: URL?
    var emoji: Emoji?
    var emojiString: String? {
        return self.emoji?.emoji
    }
}
