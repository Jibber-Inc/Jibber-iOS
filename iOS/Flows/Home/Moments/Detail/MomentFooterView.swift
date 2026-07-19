//
//  MomentFooterView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/30/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

class MomentFooterView: BaseView {
    
    let shareButton = ThemeButton()
    let commentsLabel = CommentsLabel()
    let reactionsView = MomentReactionsView()
    private var moment: Moment?
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.commentsLabel)
        self.addSubview(self.reactionsView)
        self.addSubview(self.shareButton)
        self.shareButton.set(style: .image(symbol: .share, palletteColors: [.whiteWithAlpha], pointSize: 26, backgroundColor: .clear))
    }
    
    func configure(for moment: Moment) {
        self.moment = moment
        self.commentsLabel.configure(with: moment)
        self.reactionsView.configure(with: moment)
        #if APPCLIP
        // Resharing is visible as a gated action in the read-only App Clip.
        self.shareButton.isVisible = true
        #else
        self.shareButton.isVisible = moment.isFromCurrentUser && moment.isAvailable
        #endif
        self.layoutNow()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.reactionsView.squaredSize = 35
        self.reactionsView.pinToSafeAreaRight()
        
        self.shareButton.squaredSize = 35
        self.shareButton.match(.right, to: .left, of: self.reactionsView, offset: .negative(.long))
        
        var maxWidth: CGFloat = 0
        
        if self.shareButton.isVisible {
            maxWidth = Theme.getPaddedWidth(with: self.width) - self.reactionsView.width - self.shareButton.width - Theme.ContentOffset.long.value.doubled
        } else {
            maxWidth = Theme.getPaddedWidth(with: self.width) - self.reactionsView.width - Theme.ContentOffset.long.value
        }
        
        self.commentsLabel.setSize(withWidth: maxWidth)
        self.commentsLabel.pin(.top, offset: .xtraLong)
        self.commentsLabel.pinToSafeAreaLeft()
        
        self.reactionsView.centerY = self.commentsLabel.centerY
        self.shareButton.centerY = self.commentsLabel.centerY
    }
}
