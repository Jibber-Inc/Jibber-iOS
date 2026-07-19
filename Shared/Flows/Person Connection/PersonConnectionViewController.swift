//
//  PersonConnectionViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/16/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import Localization
import Combine

class PersonConnectionViewController: ViewController {
    
    private var person: PersonType?
    
    lazy var header = ProfileHeaderView()
    let button = ThemeButton()
    
    let titleLabel = ThemeLabel(font: .regularBold)
    let descriptionLabel = ThemeLabel(font: .small)
    
    override func initializeViews() {
        super.initializeViews()
        
        self.modalPresentationStyle = .popover
        if let pop = self.popoverPresentationController {
            let sheet = pop.adaptiveSheetPresentationController
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        
        self.view.set(backgroundColor: .B0)
                
        self.view.addSubview(self.header)
        self.header.menuButton.isVisible = false
        
        self.view.addSubview(self.button)
        self.button.set(style: .custom(color: .white, textColor: .B0, text: "Connect"))
        
        self.view.addSubview(self.titleLabel)
        self.titleLabel.textAlignment = .center
        
        self.view.addSubview(self.descriptionLabel)
        self.descriptionLabel.textAlignment = .center
        self.descriptionLabel.alpha = 0.25
        
        PeopleStore.shared
            .$personUpdated
            .filter { [unowned self] updatedPerson in
                // Only handle person updates related to the currently assigned person.
                self.person?.personId ==  updatedPerson?.personId
            }.mainSink { [unowned self] person in
                guard let user = person as? User else { return }
                self.header.configure(with: user)
            }.store(in: &self.cancellables)
    }
    
    func configure(for person: PersonType, inviteMessage: String? = nil) {
        Task { [unowned self] in
            let updatedPerson = await PeopleStore.shared.getPerson(withPersonId: person.personId)
                ?? person

            guard !Task.isCancelled else { return }

            self.person = updatedPerson

            self.header.configure(with: updatedPerson)
            
            let title = LocalizedString(id: "", arguments: [updatedPerson.fullName], default: "Connect with @(name)?")

            let bodyText: String
            if let inviteMessage, !inviteMessage.isEmpty {
                bodyText = "“\(inviteMessage)”"
            } else {
                bodyText = "Accepting connects you without consuming one of your reservations."
            }
            let body = LocalizedString(id: "", arguments: [], default: bodyText)
            
            self.titleLabel.setText(title)
            self.descriptionLabel.setText(body)
            
            self.view.setNeedsLayout()
        }.add(to: self.autocancelTaskPool)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.header.expandToSuperviewWidth()
        self.header.height = ProfileHeaderView.height
        self.header.pinToSafeArea(.top, offset: .xtraLong)
        
        self.button.setSize(with: self.view.width)
        self.button.centerOnX()
        self.button.pinToSafeAreaBottom()
        
        self.descriptionLabel.setSize(withWidth: Theme.getPaddedWidth(with: self.view.width))
        self.descriptionLabel.centerOnX()
        self.descriptionLabel.match(.bottom, to: .top, of: self.button, offset: .negative(.xtraLong))
        
        self.titleLabel.setSize(withWidth: Theme.getPaddedWidth(with: self.view.width))
        self.titleLabel.centerOnX()
        self.titleLabel.match(.bottom, to: .top, of: self.descriptionLabel, offset: .negative(.standard))
    }
}
        
