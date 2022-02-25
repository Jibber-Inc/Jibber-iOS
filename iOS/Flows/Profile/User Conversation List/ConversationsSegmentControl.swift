//
//  ConversationsSegmentControl.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/22/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class ConversationsSegmentControl: UISegmentedControl {
    
    enum SegmentType: Int {
        case recents
        case all
        case archive
    }
    
    var didSelectSegmentIndex: ((SegmentType) -> Void)? = nil
    
    init() {
        
        super.init(frame: .zero)
        
        let rewardsAction = UIAction(title: "Recents") { _ in
            self.didSelectSegmentIndex?(.recents)
        }
        
        let youAction = UIAction(title: "All") { _ in
            self.didSelectSegmentIndex?(.all)
        }
        
        let connectionsAction = UIAction(title: "Archive") { _ in
            self.didSelectSegmentIndex?(.archive)
        }
            
        self.insertSegment(action: rewardsAction, at: 0, animated: false)
        self.insertSegment(action: youAction, at: 1, animated: false)
        self.insertSegment(action: connectionsAction, at: 2, animated: false)

        let attributes: [NSAttributedString.Key : Any] = [.font : FontType.small.font, .foregroundColor : ThemeColor.T1.color.withAlphaComponent(0.6)]
        self.setTitleTextAttributes(attributes, for: .normal)
        self.setTitleTextAttributes(attributes, for: .selected)
        self.setTitleTextAttributes(attributes, for: .highlighted)
        self.selectedSegmentTintColor = ThemeColor.B5.color.withAlphaComponent(0.1)
        self.selectedSegmentIndex = 0
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}