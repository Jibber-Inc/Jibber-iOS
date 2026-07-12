//
//  HomeCoordinator+Wallet.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/21/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

extension HomeCoordinator {
    
    func presentJibInfoAlert() {
                
        let alertController = UIAlertController(title: "Jibs",
                                                message: "Earn Jibs now and soon you can use them to upgrade, vote on features, or invest in Jibber.",
                                                preferredStyle: .alert)

        let cancelAction = UIAlertAction(title: "Got it", style: .cancel, handler: {
            (action : UIAlertAction!) -> Void in
        })

        alertController.addAction(cancelAction)
        self.homeVC.present(alertController, animated: true, completion: nil)
    }
    
    func presentAchievementAlert(for achievement: AchievementViewModel) {
        
        var description: String = ""
        
        if let firstDate = achievement.achievements.first?.createdAt {
            description = "\(achievement.type.descriptionText)\n\nEarned: \(Date.monthDayYear.string(from: firstDate))"
        } else {
            description = "\(achievement.type.descriptionText)\n\n(Coming Soon)"
        }

        let alertController = UIAlertController(title: achievement.type.title,
                                                message: description,
                                                preferredStyle: .alert)

        let cancelAction = UIAlertAction(title: "Got it", style: .cancel, handler: {
            (action : UIAlertAction!) -> Void in
        })

        alertController.addAction(cancelAction)
        self.homeVC.present(alertController, animated: true, completion: nil)
    }
}
