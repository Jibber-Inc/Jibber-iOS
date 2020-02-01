//
//  ProfileCoordinator.swift
//  Benji
//
//  Created by Benji Dodgson on 10/5/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Parse

class ProfileCoordinator: Coordinator<Void> {

    let profileVC: ProfileViewController

    init(router: Router,
         deepLink: DeepLinkable?,
         profileVC: ProfileViewController) {

        self.profileVC = profileVC

        super.init(router: router, deepLink: deepLink)
    }

    override func start() {

        self.profileVC.delegate = self

        if let link = self.deepLink, let target = link.deepLinkTarget, target == .routine {
            self.presentRoutine()
        }
    }

    private func presentRoutine() {
        let vc = RoutineViewController()
        self.router.present(vc, source: self.profileVC)
    }
}

extension ProfileCoordinator: ProfileViewControllerDelegate {

    func profileViewControllerDidSelectRoutine(_ controller: ProfileViewController) {
        self.presentRoutine()
    }

    func profileViewControllerDidSelectPhoto(_ controller: ProfileViewController) {
        let vc = ProfilePhotoViewController(with: self)
        self.router.present(vc, source: controller)
    }
}

extension ProfileCoordinator: ProfilePhotoViewControllerDelegate {
    func profilePhotoViewControllerDidFinish(_ controller: ProfilePhotoViewController) {
        controller.dismiss(animated: true) {
            self.profileVC.collectionView.reloadData()
        }
    }
}
