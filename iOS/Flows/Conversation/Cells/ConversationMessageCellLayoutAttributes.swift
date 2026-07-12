//
//  ConversationMessageCellAttributes.swift
//  Jibber
//
//  Created by Martin Young on 11/4/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

class ConversationMessageCellLayoutAttributes: UICollectionViewLayoutAttributes {

    /// How bright the background color is. 0 is black. 1 is full brightness of the given color
    var brightness: CGFloat = 1 {
        didSet { self.equalityBrightness = self.brightness }
    }
    /// The alpha of the detial view.
    var detailAlpha: CGFloat = 0 {
        didSet { self.equalityDetailAlpha = self.detailAlpha }
    }

    // NSObject's equality requirement is nonisolated even though UIKit layout attributes are main-thread state.
    // Mirror only the scalar values needed by isEqual instead of exposing the UI properties across actors.
    nonisolated(unsafe) private var equalityBrightness: CGFloat = 1
    nonisolated(unsafe) private var equalityDetailAlpha: CGFloat = 0

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! ConversationMessageCellLayoutAttributes
        copy.brightness = self.brightness
        copy.detailAlpha = self.detailAlpha
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        if let layoutAttributes = object as? ConversationMessageCellLayoutAttributes {
            return super.isEqual(object)
            && layoutAttributes.equalityBrightness == self.equalityBrightness
            && layoutAttributes.equalityDetailAlpha == self.equalityDetailAlpha
        }

        return false
    }
}
