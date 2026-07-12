//
//  PermissionsViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 10/27/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Intents
import Combine
import Localization
import UIKit

class PermissionsViewController: DisclosureModalViewController {

    enum State {
        case initial
        case focusAsk
        case notificationAsk
        case finished

        var title: Localized {
            switch self {
            case .initial:
                return ""
            case .focusAsk:
                return "Focus Status"
            case .notificationAsk:
                return "Notifications"
            case .finished:
                return "Success"
            }
        }

        var description: HightlightedPhrase {
            switch self {
            case .initial:
                return HightlightedPhrase(text: "",
                                          highlightedWords: [])
            case .focusAsk:
                return HightlightedPhrase(text: "Changing Focus status updates your profile so people see if you are available or busy and filters out unnecessary notifications.",
                                          highlightedWords: [])
            case .notificationAsk:
                return HightlightedPhrase(text: "Allowing Notifications means you never miss out on what’s important. No noise.",
                                          highlightedWords: [])
            case .finished:
                return HightlightedPhrase(text: "Now that you have Focus and Notifications on, you are ready for Jibber!",
                                          highlightedWords: [])
            }
        }
    }

    @Published var state: State = .initial

    private let focusSwitchView = PermissionSwitchView(with: .focus)
    private let notificationSwitchView = PermissionSwitchView(with: .notificaitons)
    let button = ThemeButton()

    override func initializeViews() {
        super.initializeViews()

        self.contentView.addSubview(self.focusSwitchView)

        self.focusSwitchView.switchView.addAction(UIAction(handler: { action in
            self.handleFocus(isON: self.focusSwitchView.isON)
        }), for: .valueChanged)

        #if !APPCLIP && !NOTIFICATION
        self.contentView.addSubview(self.notificationSwitchView)
        self.notificationSwitchView.switchView.addAction(UIAction(handler: { action in
            self.handleNotifications(isON: self.notificationSwitchView.isON)
        }), for: .valueChanged)
        #endif

        self.contentView.addSubview(self.button)
        self.button.set(style: .custom(color: .white, textColor: .B0, text: "Done"))
        self.button.isEnabled = false
        self.button.alpha = 0.1

        self.$state
            .removeDuplicates()
            .mainSink { [unowned self] state in
            self.updateUI(for: state)
        }.store(in: &self.cancellables)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if INFocusStatusCenter.default.authorizationStatus == .authorized {
            self.state = .notificationAsk
        } else {
            self.state = .focusAsk
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.button.expandToSuperviewWidth()
        self.button.height = Theme.buttonHeight
        self.button.pinToSafeAreaBottom()

        self.notificationSwitchView.setSize(with: self.view.width)
        self.notificationSwitchView.match(.bottom, to: .top, of: self.button, offset: .negative(.standard))

        self.focusSwitchView.setSize(with: self.view.width)
        self.focusSwitchView.match(.bottom, to: .top, of: self.notificationSwitchView, offset: .negative(.standard))
    }

    private func updateUI(for state: State) {

        UIView.animate(withDuration: 0.2) {
            self.titleLabel.alpha = 0.0
            self.descriptionLabel.alpha = 0.0
        } completion: { completed in
            self.titleLabel.setText(state.title)
            self.updateDescription(with: state.description)
            
            logDebug(state.title.defaultString ?? "")

            UIView.animate(withDuration: 0.2) {
                self.titleLabel.alpha = 1.0
                self.descriptionLabel.alpha = 1.0
                self.view.layoutNow()
            } completion: { _ in
                if state == .focusAsk || state == .notificationAsk {
                    Task {
                        await self.layoutSwitches()
                    }
                } else if state == .finished {
                    self.focusSwitchView.state = .hidden
                    self.notificationSwitchView.state = .hidden

                    self.button.isEnabled = true
                    self.button.alpha = 1.0
                }
            }
        }
    }

    @MainActor
    private func layoutSwitches() async {

        switch INFocusStatusCenter.default.authorizationStatus {
        case .notDetermined:
            self.focusSwitchView.state = .enabled
            self.focusSwitchView.switchView.setOn(false, animated: true)
        case .restricted, .denied:
            self.focusSwitchView.state = .disabled
            self.focusSwitchView.switchView.setOn(false, animated: true)
        case .authorized:
            self.focusSwitchView.state = .disabled
            self.focusSwitchView.switchView.setOn(true, animated: true)
        @unknown default:
            break
        }
        
        let status = await UserNotificationManager.shared.getNotificationSettings().authorizationStatus

        if status != .authorized {
            if INFocusStatusCenter.default.authorizationStatus == .authorized {
                self.notificationSwitchView.state = .enabled
                self.state = .notificationAsk
            } else {
                self.notificationSwitchView.state = .disabled
            }

        } else {
            if INFocusStatusCenter.default.authorizationStatus == .authorized, status == .authorized {
                self.state = .finished
            }
            self.notificationSwitchView.state = .enabled
            self.notificationSwitchView.switchView.setOn(true, animated: true)
        }
    }

    private func handleFocus(isON: Bool) {
        if isON, INFocusStatusCenter.default.authorizationStatus == .notDetermined {
            Task { @MainActor [weak self] in
                guard let self else { return }

                let status = await INFocusStatusCenter.default.requestAuthorization()
                if status != .authorized {
                    self.focusSwitchView.switchView.setOn(false, animated: true)
                } else if await UserNotificationManager.shared.getNotificationSettings().authorizationStatus != .authorized {
                    self.state = .notificationAsk
                    self.notificationSwitchView.state = .enabled
                } else {
                    guard let isFocused = INFocusStatusCenter.default.focusStatus.isFocused else { return }
                    let newStatus: FocusStatus = isFocused ? .focused : .available
                    User.current()?.focusStatus = newStatus
                    _ = try? await User.current()?.saveInBackground()
                }
            }
        }
    }

    #if !APPCLIP && !NOTIFICATION
    private func handleNotifications(isON: Bool) {
        Task {
            await UserNotificationManager.shared.register(application: UIApplication.shared, forceRegistration: true)
            let settings = await UserNotificationManager.shared.getNotificationSettings()
            if settings.authorizationStatus == .authorized {
                self.state = .finished
            } else {
                self.notificationSwitchView.switchView.setOn(false, animated: true)
            }
        }
    }
    #endif
}
