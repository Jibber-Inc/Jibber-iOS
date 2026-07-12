//
//  MessagePreviewViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 12/7/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator

class MessagePreviewViewController: ViewController {

    let message: Messageable

    private let content = MessageContentView()
    
    init(with message: Messageable) {
        self.message = message
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        guard let window = UIWindow.topWindow() else { return }
        
        self.content.layoutState = .full
        self.view.addSubview(self.content)
        self.content.configureBackground(color: ThemeColor.B6.color,
                                         textColor: ThemeColor.white.color,
                                         brightness: 1.0,
                                         showBubbleTail: false,
                                         tailOrientation: .up)
        self.content.configure(with: self.message)
        self.content.authorView.expressionVideoView.shouldPlay = true 

        let maxWidth = window.width - Theme.ContentOffset.xtraLong.value.doubled
        var size = self.content.getSize(with: maxWidth)
        size.width = maxWidth
        
        if size.height < MessageContentView.bubbleHeight {
            size.height = MessageContentView.bubbleHeight
        }

        self.preferredContentSize = size
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
