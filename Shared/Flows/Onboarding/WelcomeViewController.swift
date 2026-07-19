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
        case acceptInvite
        case declineInvite
        case acceptMomentInvite
        case deferMomentInvite
    }

    enum Mode {
        case standard
        case invitation
        case momentInvitation
    }
    
    var onDidComplete: ((Result<SelectionType, Error>) -> Void)?
    
    let waitlistButton = ThemeButton()
    let rsvpButton = ThemeButton()

    var mode: Mode = .standard {
        didSet {
            guard self.isViewLoaded else { return }
            self.updateButtons()
        }
    }
        
    override var analyticsIdentifier: String? {
        return "SCREEN_WELCOME"
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.addSubview(self.waitlistButton)
        self.waitlistButton.didSelect { [unowned self] in
            switch self.mode {
            case .standard:
                AnalyticsManager.shared.trackEvent(type: .onboardingBeginTapped, properties: nil)
                self.onDidComplete?(.success(.waitlist))
            case .invitation:
                self.onDidComplete?(.success(.acceptInvite))
            case .momentInvitation:
                self.onDidComplete?(.success(.acceptMomentInvite))
            }
        }
        
        self.view.addSubview(self.rsvpButton)
        self.rsvpButton.didSelect { [unowned self] in
            switch self.mode {
            case .standard:
                AnalyticsManager.shared.trackEvent(type: .onboardingRSVPTapped, properties: nil)
                self.onDidComplete?(.success(.rsvp))
            case .invitation:
                self.onDidComplete?(.success(.declineInvite))
            case .momentInvitation:
                self.onDidComplete?(.success(.deferMomentInvite))
            }
        }

        self.updateButtons()
    }

    private func updateButtons() {
        switch self.mode {
        case .standard:
            self.waitlistButton.set(
                style: .custom(color: .D1, textColor: .white, text: "Join Waitlist / Login")
            )
            self.rsvpButton.set(
                style: .custom(color: .white, textColor: .B0, text: "Enter Invite Code")
            )
        case .invitation:
            self.waitlistButton.set(
                style: .custom(color: .D1, textColor: .white, text: "Accept Invite")
            )
            self.rsvpButton.set(
                style: .custom(color: .white, textColor: .B0, text: "Decline")
            )
        case .momentInvitation:
            self.waitlistButton.set(
                style: .custom(color: .D1, textColor: .white, text: "Connect & Continue")
            )
            self.rsvpButton.set(
                style: .custom(color: .white, textColor: .B0, text: "Not Now")
            )
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
