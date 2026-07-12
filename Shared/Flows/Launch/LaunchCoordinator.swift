//
//  LaunchCoordinator.swift
//  Jibber
//
//  Created by Martin Young on 1/12/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit
import Coordinator
import ParseCore

enum LaunchResult {
    case success(DeepLinkable?)
    case failed
}

class LaunchCoordinator: PresentableCoordinator<LaunchResult> {

    lazy var splashVC = SplashViewController()

    override func toPresentable() -> DismissableVC {
        return self.splashVC
    }

    override func start() {
        super.start()

        self.startLaunchTask()
    }

    private var launchTask: Task<Void, Never>?
    private var retryCount: Int = 0

    private func startLaunchTask() {
        self.splashVC.startLoadAnimation()

        self.launchTask?.cancel()

        self.launchTask = Task { [weak self] in
            let launchStatus = await LaunchManager.shared.launchApp(with: self?.deepLink)

            guard !Task.isCancelled else { return }

            self?.handle(launchStatus: launchStatus)
        }
    }

    private func handle(launchStatus: LaunchStatus) {
        switch launchStatus {
        case .success(let deepLink):
            self.finishFlow(with: .success(deepLink))
        case .updateRequired(let message):
            self.presentUpdateRequiredAlert(message: message)
        case .failed(let error, let deepLink):
            self.splashVC.stopLoadAnimation()
            if self.retryCount == 1 {
                self.finishFlow(with: .failed)
            } else if let e = error {
                switch e.code {
                case 141:
                    self.handleInvalidSessionError(with: deepLink)
                default:
                    self.presentErrorAlert(with: error)
                }
            } else {
                self.presentErrorAlert(with: error)
            }
        }
    }

    private func presentUpdateRequiredAlert(message: String) {
        self.splashVC.stopLoadAnimation()
        let alert = UIAlertController(
            title: "Update Required",
            message: message + " Please update Jibber from the App Store to continue.",
            preferredStyle: .alert
        )
        // There is intentionally no bypass or retry action: the server has
        // declared this client incompatible with the messaging contract.
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.splashVC.present(alert, animated: true)
    }
    
    private func handleInvalidSessionError(with deepLink: DeepLinkable?) {
        Task {
            guard let token = User.getStoredSessionToken() else { return }
            
            do {
                try await User.become(withSessionToken: token)
                self.finishFlow(with: .success(deepLink))
            }
            catch {
                self.finishFlow(with: .failed)
            }
        }
    }

    private func presentErrorAlert(with error: ClientError?) {
        let alert = UIAlertController(title: "Unable to login",
                                      message: "Check your connection and please try again.",
                                      preferredStyle: .alert)
        let ok = UIAlertAction(title: "Retry", style: .default) { [unowned self] (_) in
            self.retryCount += 1
            self.startLaunchTask()
        }

        alert.addAction(ok)

        self.splashVC.present(alert, animated: true)
    }
}
