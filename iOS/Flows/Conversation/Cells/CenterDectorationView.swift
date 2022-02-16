//
//  CenterDectorationView.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/3/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import StreamChat

class CenterDectorationView: UICollectionReusableView, ConversationUIStateSettable {
    static let kind = "decoration"
    let imageView = UIImageView()
    
    let leftLabel = ThemeLabel(font: .small, textColor: .D1)
    let rightLabel = ThemeLabel(font: .small, textColor: .D1)
        
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initializeSubviews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func initializeSubviews() {
        self.addSubview(self.leftLabel)
        self.leftLabel.textAlignment = .left
        self.addSubview(self.rightLabel)
        self.rightLabel.textAlignment = .right
        self.addSubview(self.imageView)
        self.imageView.contentMode = .scaleAspectFit
    }
        
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.imageView.squaredSize = 14
        self.imageView.centerOnXAndY()
        
        self.leftLabel.setSize(withWidth: 120)
        self.leftLabel.match(.right, to: .left, of: self.imageView, offset: .negative(.screenPadding))
        self.leftLabel.centerOnY()
        
        self.rightLabel.setSize(withWidth: 120)
        self.rightLabel.match(.left, to: .right, of: self.imageView, offset: .screenPadding)
        self.rightLabel.centerOnY()
    }
    
    func set(state: ConversationUIState) {
        switch state {
        case .read:
            self.imageView.image = UIImage(named: "Collapse")
        case .write:
            self.imageView.image = UIImage(named: "Expand")
        }
    }
    
    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        
        if let attributes = layoutAttributes as? DecorationViewLayoutAttributes {
            self.set(state: attributes.state)
        }
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}
