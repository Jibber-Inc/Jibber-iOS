//
//  UserProfileViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 1/18/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import Combine

class PersonPreviewViewController: ViewController {

    private let person: PersonType
    
    private let content = ProfileHeaderView()

    init(with person: PersonType) {
        self.person = person
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        self.view.set(backgroundColor: .B0)
        self.view.addSubview(self.content)
        self.content.menuButton.isVisible = false 

        let objectId = self.person.personId
        Task { [weak self] in
            guard let self else { return }
            guard let person = await PeopleStore.shared.getPerson(withPersonId: objectId) else { return }
            self.content.configure(with: person)
        }
        
        guard let window = UIWindow.topWindow() else { return }

        self.preferredContentSize = CGSize(width: Theme.getPaddedWidth(with: window.width), height: ProfileHeaderView.height + Theme.ContentOffset.xtraLong.value.doubled)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.content.expandToSuperviewWidth()
        self.content.height = ProfileHeaderView.height
        self.content.centerOnXAndY()
    }
}
