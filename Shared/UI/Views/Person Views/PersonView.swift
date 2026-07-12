//
//  PersonView.swift
//  Benji
//
//  Created by Benji Dodgson on 6/23/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Combine
import Foundation
import UIKit

class PersonView: DisplayableImageView {
    
    // MARK: - Properties
    
    var didTapViewProfile: CompletionOptional = nil 

    func getSize(forHeight height: CGFloat) -> CGSize {
        return CGSize(width: height, height: height)
    }

    func setSize(forHeight height: CGFloat) {
        self.size = self.getSize(forHeight: height)
    }
    
    override func initializeSubviews() {
        super.initializeSubviews()

        #if IOS
        let interaction = UIContextMenuInteraction(delegate: self)
        self.addInteraction(interaction)
        
        self.didTapViewProfile = { [unowned self] in
            var dl = DeepLinkObject(target: .profile)
            dl.personId = self.person?.personId ?? ""
            LaunchManager.shared.delegate?.launchManager(LaunchManager.shared, didReceive: .deepLink(dl))
        }
        
        #endif

        self.subscribeToUpdates()
    }

    // MARK: - Open setters

    func set(person: PersonType?) {
        #if IOS
        self.person = person
        #endif
        self.displayable = person
    }

    // MARK: - Subscriptions

    /// Called when the currently assigned person receives an update to their state.
    func didRecieveUpdateFor(person: PersonType) {
        self.displayable = person
    }

    private func subscribeToUpdates() {
        PeopleStore.shared.$personUpdated
            .filter { [unowned self] updatedPerson in
                // Only handle person updates related to the currently assigned person.
                if let person = displayable as? PersonType {
                    return person.personId == updatedPerson?.personId
                } else {
                    return false
                }
            }.mainSink { [unowned self] updatedPerson in
                guard let updatedPerson = updatedPerson else { return }
                self.didRecieveUpdateFor(person: updatedPerson)
            }.store(in: &self.cancellables)
    }
}
