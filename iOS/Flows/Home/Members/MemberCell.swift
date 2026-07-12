//
//  CircleCell.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/26/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import ParseCore

class MemberCell: CollectionViewManagerCell, ManageableCell {

    typealias ItemType = String
    var currentItem: String?
    
    private let personView = BorderedPersonView()
    private let label = ThemeLabel(font: .regular, textColor: .whiteWithAlpha)
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.contentView.addSubview(self.personView)
        self.contentView.addSubview(self.label)
        self.label.textAlignment = .center
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.label.setSize(withWidth: self.contentView.width)
        self.label.match(.top, to: .bottom, of: self.contentView, offset: .standard)
        self.label.centerOnX()
        
        self.personView.squaredSize = self.contentView.height
        self.personView.centerOnX()
        self.personView.pin(.top)
    }

    func configure(with item: String) {
        Task.onMainActorAsync { [self] in
            guard let person = await PeopleStore.shared.getPerson(withPersonId: item) else { return }
            let expression = await MomentsStore.shared.getTodaysMoment(withPersonId: item)?.expression
            self.personView.set(expression: expression, person: person)
            if person.isCurrentUser {
                self.label.setText(person.givenName + " (You)")
            } else {
                self.label.setText(person.givenName)
            }
            self.layoutNow()
            
            MomentsStore.shared.$todaysMoments.mainSink { [unowned self] moments in
                if let first = moments.first(where: { moment in
                    return moment.author?.objectId == person.personId
                }) {
                    Task {
                        self.personView.set(expression: first.expression, person: person)
                        self.personView.expressionVideoView.shouldPlay = true
                        self.personView.expressionVideoView.shouldPlayAudio = false 
                    }
                }
            }.store(in: &self.cancellables)
        }
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)

        guard let memberCellAttributes = layoutAttributes as? MemberCellLayoutAttributes else { return }

        self.contentView.alpha = memberCellAttributes.alpha 
        self.personView.expressionVideoView.shouldPlay = memberCellAttributes.isCentered
    }
}
