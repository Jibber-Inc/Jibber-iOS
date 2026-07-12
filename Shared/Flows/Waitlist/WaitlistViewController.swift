//
//  WaitlistViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 4/12/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import ParseLiveQuery
import Transitions

class WaitlistViewController: ViewController {
    
    override var analyticsIdentifier: String? {
        return "SCREEN_WAITLIST"
    }
    
    let personView = BorderedPersonView()
    let titleLabel = ThemeLabel(font: .display)
    let descriptionLabel = ThemeLabel(font: .regular)
    let button = ThemeButton()
    private var shouldShowButton = false
    var shouldDisplayUpdateOverlay: CompletionOptional = nil
    
    override func initializeViews() {
        super.initializeViews()
                
        self.view.set(backgroundColor: .B0)
        
        self.view.addSubview(self.personView)
        self.personView.isVisible = false
        self.view.addSubview(self.titleLabel)
        self.titleLabel.textAlignment = .center
        self.view.addSubview(self.descriptionLabel)
        self.descriptionLabel.textAlignment = .center
        
        self.view.addSubview(self.button)
        self.button.alpha = 0.0
        
        PeopleStore.shared.$personUpdated.filter({ type in
            return type?.isCurrentUser ?? false
        }).mainSink { type in
            self.updateUI()
        }.store(in: &self.cancellables)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.updateUI()
    }
    
    override func willEnterForeground() {
        super.willEnterForeground()
        
        self.updateUI()
    }
    
    /// The currently running task that is loading conversations.
    private var loadTask: Task<Void, Never>?
    
    private func updateUI() {
        self.loadTask?.cancel()
        
        self.loadTask = Task { [weak self] in
            guard let self else { return }
            
            guard let user = try? await User.current()?.retrieveDataIfNeeded() else { return }
                        
            switch user.status {
            case .active:
                self.titleLabel.setText("Congrats! 🥳")
                self.descriptionLabel.setText("You now have access to join Jibber!")
            case .waitlist:
                if let position = user.quePosition {
                    self.titleLabel.setText("You're #\(position)")
                    self.descriptionLabel.setText("Jibber works best with people you know,\n so share it to get immediate access.")
                }
            default:
                break
            }
            
            self.displayNextStep(for: user)

            self.view.setNeedsLayout()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.titleLabel.setSize(withWidth: Theme.getPaddedWidth(with: self.view.width))
        self.titleLabel.centerY = self.view.height * 0.45
        self.titleLabel.centerOnX()
        
        self.descriptionLabel.setSize(withWidth: Theme.getPaddedWidth(with: self.view.width))
        self.descriptionLabel.match(.top, to: .bottom, of: self.titleLabel, offset: .long)
        self.descriptionLabel.centerOnX()
        
        self.personView.squaredSize = 100
        self.personView.centerOnX()
        self.personView.match(.bottom, to: .top, of: self.titleLabel, offset: .negative(.screenPadding))
        
        self.button.setSize(with: self.view.width)
        self.button.centerOnX()
        if self.shouldShowButton {
            self.button.pinToSafeAreaBottom()
        } else {
            self.button.top = self.view.height
        }
    }
    
    func displayNextStep(for user: User) {
        if user.status == .active {
            self.button.set(style: .custom(color: .white, textColor: .B0, text: "Enter"))
        } else if user.status == .waitlist {
            self.button.set(style: .custom(color: .white, textColor: .B0, text: "Share for Access"))
        }
        
        #if IOS
        Task {
            self.shouldShowButton = user.status == .active
            if user.status == .waitlist, let _ = try? await Pass.fetchPass() {
                self.shouldShowButton = true
            }
            await UIView.awaitAnimation(with: .fast, animations: {
                if self.shouldShowButton {
                    self.button.alpha = 1.0
                    self.view.layoutNow()
                } else {
                    self.button.alpha = 0.0
                    self.view.layoutNow()
                }
            })
        }
        #else
        self.shouldDisplayUpdateOverlay?()
        #endif
    }
}

extension WaitlistViewController: TransitionableViewController {

    var presentationType: TransitionType {
        return .fadeOutIn
    }

    var dismissalType: TransitionType {
        return self.presentationType
    }

    func getFromVCPresentationType(for toVCPresentationType: TransitionType) -> TransitionType {
        return toVCPresentationType
    }

    func getToVCDismissalType(for fromVCDismissalType: TransitionType) -> TransitionType {
        return fromVCDismissalType
    }
}
