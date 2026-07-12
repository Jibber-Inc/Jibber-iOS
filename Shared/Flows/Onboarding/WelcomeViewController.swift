//
//  newWelcomeViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 12/30/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Coordinator
import Foundation
import ParseCore
import Combine

class WelcomeViewController: ViewController, Sizeable, Completable {
    
    typealias ResultType = SelectionType
    
    enum SelectionType {
        case waitlist
        case rsvp
    }
    
    var onDidComplete: ((Result<SelectionType, Error>) -> Void)?
    
    let waitlistButton = ThemeButton()
    let rsvpButton = ThemeButton()
        
    override var analyticsIdentifier: String? {
        return "SCREEN_WELCOME"
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.addSubview(self.waitlistButton)
        self.waitlistButton.set(style: .custom(color: .D1, textColor: .white, text: "Join Waitlist / Login"))
        self.waitlistButton.didSelect { [unowned self] in
            AnalyticsManager.shared.trackEvent(type: .onboardingBeginTapped, properties: nil)
            self.onDidComplete?(.success((.waitlist)))
        }
        
        self.view.addSubview(self.rsvpButton)
        self.rsvpButton.set(style: .custom(color: .white, textColor: .B0, text: "Enter Invite Code"))
        self.rsvpButton.didSelect { [unowned self] in
            AnalyticsManager.shared.trackEvent(type: .onboardingRSVPTapped, properties: nil)
            self.onDidComplete?(.success((.rsvp)))
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.rsvpButton.setSize(with: self.view.width)
        self.rsvpButton.pinToSafeAreaBottom()
        self.rsvpButton.centerOnX()
        
        self.waitlistButton.setSize(with: self.view.width)
        self.waitlistButton.match(.bottom, to: .top, of: self.rsvpButton, offset: .negative(.standard))
        
        self.waitlistButton.centerOnX()
    }
}
