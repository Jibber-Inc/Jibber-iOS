//
//  MessageExpressionCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/27/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

class MessageExpressionCell: CollectionViewManagerCell, ManageableCell {
    typealias ItemType = ExpressionInfo
    
    var currentItem: ExpressionInfo?
    
    let content = ExpressionContentView()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.contentView.clipsToBounds = false
        self.contentView.addSubview(self.content)
        self.content.personView.expressionVideoView.shouldPlay = true 
    }

    func configure(with item: ExpressionInfo) {
        self.content.configure(with: item)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.content.expandToSuperviewSize()
    }
}

class ExpressionContentView: BaseView {
    
    let personView = PersonGradientView()
    let label = ThemeLabel(font: .small)
    
    private(set) var personId: String?
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.personView)
        self.addSubview(self.label)
                
        self.label.textAlignment = .center
        self.label.alpha = 0.25
        
        self.clipsToBounds = false
    }
    
    /// A reference to a task for configuring the cell.
    private var configurationTask: Task<Void, Never>?

    func configure(with item: ExpressionInfo) {
        self.configurationTask?.cancel()
        
        self.personView.isVisible = true

        self.configurationTask = Task { [weak self] in
            guard let self else { return }
            
            guard let expression = try? await Expression.getObject(with: item.expressionId) else {
                self.isVisible = false
                return
            }
            
            self.isVisible = true 

            self.personView.set(expression: expression, person: nil)
            let dateString = expression.createdAt?.getTimeAgo().string
            self.label.setText(dateString)
            
            self.setNeedsLayout()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.personView.squaredSize = self.width
        self.personView.centerOnX()
        self.personView.pin(.top)
        
        self.label.setSize(withWidth: self.width * 1.5)
        self.label.centerOnX()
        self.label.match(.top, to: .bottom, of: self.personView, offset: .short)
    }
}
