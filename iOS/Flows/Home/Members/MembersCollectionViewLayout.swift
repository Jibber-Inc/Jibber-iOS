//
//  MemberCollectionViewLayout.swift
//  Jibber
//
//  Created by Martin Young on 8/9/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class MemberCellLayoutAttributes: UICollectionViewLayoutAttributes {

    /// If true, the cell is centered on the screen.
    var isCentered = false {
        didSet { self.equalityIsCentered = self.isCentered }
    }

    // NSObject's equality requirement is nonisolated even though UIKit layout attributes are main-thread state.
    // Mirror only the scalar value needed by isEqual instead of exposing the UI property across actors.
    nonisolated(unsafe) private var equalityIsCentered = false

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! MemberCellLayoutAttributes
        copy.isCentered = self.isCentered
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let layoutAttributes = object as? MemberCellLayoutAttributes else { return false }

        return super.isEqual(object)
        && layoutAttributes.equalityIsCentered == self.equalityIsCentered
    }
}

class MembersCollectionViewLayout: OrbCollectionViewLayout {

    override class var layoutAttributesClass: AnyClass {
        return MemberCellLayoutAttributes.self
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let attributes = super.layoutAttributesForItem(at: indexPath) as? MemberCellLayoutAttributes else {
            return nil
        }

        // Let cells know that they're centered.
        let isCentered = attributes.center.distanceTo(self.collectionViewCenter) < 1
        attributes.isCentered = isCentered

        return attributes
    }

}
