//
//  FullScreenViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 12/25/18.
//  Copyright © 2018 Benjamin Dodgson. All rights reserved.
//

import Foundation

// Base class for all full screen view controllers pushed onto a UINavigationController stack.
// Contains a custom navigation bar that replaces the standard navigation bar. View content is
// placed in the space below the nav bar.
class FullScreenViewController: ViewController {

    // A view to insert content. Takes up the space below the custom nav bar
    let contentContainer = View()

    var isNavBarHidden: Bool = false {
        didSet {
            self.view.setNeedsLayout()
        }
    }

    override init() {
        super.init()
    }

    required init?(withObject object: DeepLinkable) {
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.set(backgroundColor: .background1)
        self.view.addSubview(self.contentContainer)
       // self.navigationController?.setNavigationBarHidden(true, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.contentContainer.top = self.view.safeAreaInsets.top
        self.contentContainer.width = self.view.width
        let height = self.view.height - self.view.safeAreaInsets.top - self.view.safeAreaInsets.bottom
        self.contentContainer.height = height
        self.contentContainer.centerOnX()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Force hide keyboard so it dimisses at the same time as view controller
        self.view.endEditing(true)
    }
}

