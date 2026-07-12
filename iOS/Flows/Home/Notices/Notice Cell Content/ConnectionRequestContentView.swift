//
//  ConnectionRequestContentView.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/24/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

class ConnectionRequestContentView: NoticeDetailContentView {
    
    override func configure(for notice: SystemNotice) async {
        await super.configure(for: notice)
        
        guard let connectionId = notice.attributes?["connectionId"] as? String,
              let connection = PeopleStore.shared.allConnections.first(where: { existing in
                  return existing.objectId == connectionId
              }), let nonMeUser = connection.nonMeUser else {
            self.showError()
            return }
        
        self.titleLabel.setText(nonMeUser.fullName)
        self.descriptionLabel.setText("Would like to connect with you.")
        
        self.imageView.set(person: nonMeUser)
        self.rightButtonLabel.setText("Accept")
        self.leftButtonLabel.setText("Decline")
        
        self.setNeedsLayout()
    }
}
