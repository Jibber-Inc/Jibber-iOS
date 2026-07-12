//
//  UrgentMessageContentView.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/24/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class UrgentMessageContentView: NoticeContentView {
    
    lazy var shadowLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.shadowColor = ThemeColor.D6.color.cgColor
        layer.shadowOpacity = 1.0
        layer.shadowOffset = .zero
        layer.shadowRadius = 8
        return layer
    }()
    
    let messageConentView = MessageContentView()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.layer.insertSublayer(self.shadowLayer, at: 0)
        self.addSubview(self.messageConentView)
    }
    
    override func configure(for notice: SystemNotice) async {
        await super.configure(for: notice)
        
        guard let cidValue = (notice.attributes?["conversationId"] as? String)
                ?? (notice.attributes?["cid"] as? String),
              let messageId = notice.attributes?["messageId"] as? String else {
            self.showError()
            return }

        let controller = ParseMessageController(
            conversationID: cidValue,
            messageID: messageId,
            automaticallySynchronize: false
        )
        try? await controller.synchronize()

        guard let message = controller.message else {
            self.showError()
            return
        }
        
        self.messageConentView.configure(with: message)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.messageConentView.expandToSuperviewSize()
        self.shadowLayer.shadowPath = UIBezierPath(rect: self.messageConentView.bounds).cgPath
    }
}
