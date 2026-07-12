//
//  ProfileHeaderView.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/22/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

class ProfileHeaderView: BaseView {
    
    static let height: CGFloat = 160
    
    let nameLabel = ThemeLabel(font: .mediumBold)
    
    let positionLabel = ThemeLabel(font: .small)
    let memberLabel = ThemeLabel(font: .regular)
    
    let localLabel = ThemeLabel(font: .small)
    let timeLabel = LocalTimeLabel(font: .regular)
    
    let focusLabel = ThemeLabel(font: .small)
    let focusCircle = BaseView()
        
    let personView = BorderedPersonView()
    
    let menuButton = ThemeButton()
    
    var didSelectUpdateProfilePicture: CompletionOptional = nil
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.personView.contextCueView.scale = .large
        self.personView.contextCueView.isVisible = false
        
        self.addSubview(self.nameLabel)
        
        self.addSubview(self.positionLabel)
        self.positionLabel.textAlignment = .center
        self.positionLabel.alpha = 0.25
        self.positionLabel.setText("Member")
        
        self.addSubview(self.memberLabel)
        
        self.addSubview(self.localLabel)
        self.localLabel.textAlignment = .center
        self.localLabel.alpha = 0.25
        self.localLabel.setText("Local Time")
        
        self.addSubview(self.timeLabel)
        self.timeLabel.textAlignment = .center
        
        self.addSubview(self.focusLabel)
        self.focusLabel.setTextColor(.D1)
        
        self.addSubview(self.focusCircle)
        self.addSubview(self.personView)
        
        self.addSubview(self.menuButton)
        self.menuButton.set(style: .image(symbol: .ellipsis, palletteColors: [.whiteWithAlpha], pointSize: 22, backgroundColor: .clear))
        self.menuButton.showsMenuAsPrimaryAction = true
    }
    
    @MainActor
    func configure(with person: PersonType) {
        
        Task {
            guard let person = await PeopleStore.shared.getPerson(withPersonId: person.personId) else { return }
            self.personView.set(expression: nil, person: person)
        }
        
        self.nameLabel.setText(person.givenName)

        if let user = person as? User {
            if let position = user.quePosition {
                self.memberLabel.setText("#\(position)")
            }

            self.timeLabel.configure(with: user)
        }

        if let status = person.focusStatus {
            self.focusLabel.setText(status.displayName.firstCapitalized)
            self.focusLabel.setTextColor(status.color)
            self.focusCircle.set(backgroundColor: status.color)
        } else {
            self.focusLabel.setTextColor(.yellow)
            self.focusLabel.setText("Unavailable")
            self.focusCircle.set(backgroundColor: FocusStatus.focused.color)
        }
        
        self.menuButton.menu = self.createMenu(for: person)
        
        self.setNeedsLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.personView.squaredSize = 100
        self.personView.centerOnX()
        self.personView.pin(.top)
        
        self.localLabel.setSize(withWidth: self.width)
        self.localLabel.centerX = self.width * 0.2
        self.localLabel.bottom = self.personView.bottom
        
        self.timeLabel.centerX = self.localLabel.centerX
        self.timeLabel.match(.bottom, to: .top, of: self.localLabel, offset: .negative(.short))
        
        self.nameLabel.setSize(withWidth: self.width)
        self.nameLabel.match(.top, to: .bottom, of: self.personView, offset: .xtraLong)
        self.nameLabel.centerOnX()
        
        self.focusLabel.setSize(withWidth: self.width)
        self.focusLabel.centerX = self.halfWidth + 7
        self.focusLabel.match(.top, to: .bottom, of: self.nameLabel, offset: .standard)
        
        self.focusCircle.squaredSize = 10
        self.focusCircle.makeRound()
        self.focusCircle.match(.right, to: .left, of: self.focusLabel, offset: .negative(.short))
        self.focusCircle.centerY = self.focusLabel.centerY
    
        self.positionLabel.setSize(withWidth: self.width)
        self.positionLabel.centerX = self.width * 0.8
        self.positionLabel.match(.bottom, to: .bottom, of: self.personView)
        
        self.memberLabel.setSize(withWidth: self.width)
        self.memberLabel.match(.bottom, to: .top, of: self.positionLabel, offset: .negative(.short))
        self.memberLabel.centerX = self.positionLabel.centerX
        
        self.menuButton.squaredSize = 44
        self.menuButton.pin(.right)
        self.menuButton.pin(.top, offset: .custom(40))
    }
    
    private func createMenu(for person: PersonType) -> UIMenu? {
        guard person.isCurrentUser else { return nil }
        
        let update = UIAction(title: "Update Picture",
                              image: ImageSymbol.camera.image,
                              attributes: []) { [unowned self] action in
            self.didSelectUpdateProfilePicture?()
        }
        
        let logout = UIAction(title: "Log Out",
                              image: ImageSymbol.exclamationmarkTriangle.image,
                              attributes: []) { _ in
            SessionManager.shared.didRecieveReuestToLogOut?()
        }

        return UIMenu.init(title: "Menu",
                           image: nil,
                           identifier: nil,
                           options: [],
                           children: [update, logout])
    }
}
