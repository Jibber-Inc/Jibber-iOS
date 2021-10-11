//
//  LinkCellAttributesConfigurer.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/4/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

class LinkCellAttributesConfigurer: ConversationCellAttributesConfigurer {

    var avatarSize = CGSize(width: 30, height: 36)
    private let widthRatio: CGFloat = 0.8

    override func configure(with message: Messageable,
                            previousMessage: Messageable?,
                            nextMessage: Messageable?,
                            for layout: ConversationThreadCollectionViewLayout,
                            attributes: ConversationCollectionViewLayoutAttributes) {

        attributes.attributes.avatarFrame = self.getAvatarFrame(with: message, layout: layout)
        attributes.attributes.attachmentFrame = self.getAttachmentFrame(with: message, layout: layout)
    }

    override func size(with message: Messageable?, for layout: ConversationThreadCollectionViewLayout) -> CGSize {
        guard let msg = message else { return .zero }

        return CGSize(width: 19, height: self.getAttachmentFrame(with: msg, layout: layout).height)
    }

    private func getAttachmentFrame(with message: Messageable, layout: ConversationThreadCollectionViewLayout) -> CGRect {

        let attachmentWidth = 19 * 0.8

        var xOffset: CGFloat = 0
        if message.isFromCurrentUser {
            xOffset = 10 - attachmentWidth - Theme.contentOffset.half
        } else {
            xOffset = self.getAvatarFrame(with: message, layout: layout).width + (self.getAvatarPadding(for: layout) * 2) + Theme.contentOffset.half
        }

        let rect = CGRect(x: xOffset,
                          y: 0,
                          width: attachmentWidth,
                          height: attachmentWidth * 1.1)
        return rect
    }

    private func getAvatarFrame(with message: Messageable, layout: ConversationThreadCollectionViewLayout) -> CGRect {
        let xOffset: CGFloat = self.getAvatarPadding(for: layout)
        return CGRect(x: xOffset,
                      y: 0,
                      width: .zero,
                      height: .zero)
    }

    private func getAvatarPadding(for layout: ConversationThreadCollectionViewLayout) -> CGFloat {
        return  8
    }
}
