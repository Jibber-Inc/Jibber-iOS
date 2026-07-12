//
//  PermissionsCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 10/27/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator

class PermissionsCoordinator: PresentableCoordinator<Void> {

    lazy var permissionsVC = PermissionsViewController()

    override func toPresentable() -> DismissableVC {
        return self.permissionsVC
    }

    override func start() {
        super.start()

        self.permissionsVC.button.didSelect { [weak self] in
            guard let self else { return }
            self.finishFlow(with: ())
        }
    }
}
