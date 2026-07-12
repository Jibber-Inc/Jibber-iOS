//
//  MainCoordinator+Extensions.swift
//  Benji
//
//  Created by Benji Dodgson on 12/16/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Coordinator
import JibberParseLiveQuery

extension MainCoordinator: LaunchManagerDelegate {

    func launchManager(_ manager: LaunchManager, didReceive activity: LaunchActivity) {
        switch activity {
        case .deepLink(let deepLinkable):
            self.handle(deeplink: deepLinkable)
        default:
            if let furthestChild = self.furthestChild as? LaunchActivityHandler {
                furthestChild.handle(launchActivity: activity)
            } else {
                // We may not have completed launching yet, so store it
                self.launchActivity = activity
            }
        }
    }

    func subscribeToUserUpdates() {
        PeopleStore.shared.$personDeleted
            .filter({ person in
                guard let personId = person?.personId else { return false }
                return personId == User.current()?.personId
            })
            .mainSink { [unowned self] user in
                self.logOut()
            }.store(in: &self.cancellables)
    }

#if APPCLIP
    func handleAppClip(deepLink object: DeepLinkable) {
        self.deepLink = object
        if let target = object.deepLinkTarget,
            target == .moment,
           let user = User.current(),
           user.status == .active {
            self.runWaitlistFlow(with: object)
        } else {
            self.runOnboardingFlow(with: object)
        }
    }
#endif
}

extension MainCoordinator: ToastSchedulerDelegate {

    func didInteractWith(type: ToastType, deeplink: DeepLinkable?) {
        guard let link = deeplink else { return }
        self.handle(deeplink: link)
    }
}
