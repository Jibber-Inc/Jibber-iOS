//
//  MomentPreviewViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/6/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator

class MomentPreviewViewController: ViewController {

    let moment: Moment

    private lazy var content = MomentContentView(with: self.moment)
    
    init(with moment: Moment) {
        self.moment = moment
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        guard let window = UIWindow.topWindow() else { return }
        
        self.view.addSubview(self.content)

        self.content.menuButton.isHidden = true
        self.content.blurView.button.isHidden = true 
        let maxWidth = window.width - Theme.ContentOffset.xtraLong.value.doubled

        self.preferredContentSize = CGSize(width: maxWidth, height: window.height * 0.7)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.view.layoutNow()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.content.expandToSuperviewSize()
    }
}
