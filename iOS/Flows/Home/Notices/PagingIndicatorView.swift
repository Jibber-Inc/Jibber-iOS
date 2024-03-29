//
//  NoticeFooterView.swift
//  Jibber
//
//  Created by Benji Dodgson on 4/19/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

extension Notification.Name {
    static let onNoticeIndexChanged = Notification.Name("onNoticeIndexChanged")
    static let onExpressionIndexChanged = Notification.Name("onExpressionIndexChanged")
}

class PagingIndicatorView: BaseView {
    
    let pageIndicator = UIPageControl()
    
    private let name: Notification.Name
    
    init(with name: Notification.Name) {
        self.name = name
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.pageIndicator)
        self.pageIndicator.preferredIndicatorImage = ImageSymbol.minus.image
        self.pageIndicator.currentPageIndicatorTintColor = ThemeColor.white.color
        self.pageIndicator.pageIndicatorTintColor = ThemeColor.B2.color
        self.pageIndicator.hidesForSinglePage = true
                
        NotificationCenter.default.publisher(for: self.name)
            .removeDuplicates(by: { lhs, rhs in
                if let lIndex = lhs.object as? Int, let rIndex = rhs.object as? Int {
                    return lIndex == rIndex
                } else {
                    return false
                }
            }).mainSink { [unowned self] output in
                guard let index = output.object as? Int else { return }
                self.pageIndicator.currentPage = index
            }.store(in: &self.cancellables)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.pageIndicator.sizeToFit()
        self.pageIndicator.centerOnX()
        self.pageIndicator.pin(.top)
    }
}
