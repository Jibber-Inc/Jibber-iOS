//
//  NoticesCollectionView.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/9/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine

class NoticesCollectionView: CollectionView {
    
    var cancellables = Set<AnyCancellable>()
    
    let label = ThemeLabel(font: .medium)
    
    init() {
        super.init(layout: NoticesCollectionViewLayout())
        
        guard let superview = UIWindow.topWindow() else { return }

        let offset = superview.height * 0.6 - 220
        self.contentInset = UIEdgeInsets(top: offset,
                                         left: 0,
                                         bottom: 0,
                                         right: 0)

    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.backView.addSubview(self.label)
        self.label.textAlignment = .center
        self.label.setText("You are all caught up! 😄")
        self.label.alpha = 0
        
        NoticeStore.shared.$notices.mainSink { [unowned self] notices in
            Task {
                await UIView.awaitAnimation(with: .fast, delay: 0.25, animations: { [unowned self] in
                    self.label.alpha = notices.count == 0 ? 1.0 : 0.0
                })
            }
        }.store(in: &self.cancellables)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.label.setSize(withWidth: Theme.getPaddedWidth(with: self.width))
        self.label.centerOnXAndY()
    }
}
