//
//  MessageReadContentView.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/24/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class MessageReadContentView: BaseView {
    
    let personView = BorderedPersonView()
    let label = ThemeLabel(font: .xtraSmall)
    
    private(set) var personId: String?
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.personView)
        self.addSubview(self.label)
        
        self.personView.contextCueView.scale = .small
        
        self.label.textAlignment = .center
        self.label.alpha = 0.25
        
        self.clipsToBounds = false 
    }
    
    /// A reference to a task for configuring the cell.
    private var configurationTask: Task<Void, Never>?

    func configure(with item: ReadViewModel) {
        self.configurationTask?.cancel()
        
        guard let authorId = item.authorId else {
            self.personView.isVisible = false
            return
        }
        
        self.personView.isVisible = true

        self.configurationTask = Task { [weak self] in
            guard let self else { return }
            
            guard let person = await PeopleStore.shared.getPerson(withPersonId: authorId) else { return }

            self.personView.set(person: person)
            let dateString = item.createdAt?.getTimeAgo().string
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
