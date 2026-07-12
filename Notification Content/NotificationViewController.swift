//
//  NotificationViewController.swift
//  OursNotificationContent
//
//  Created by Benji Dodgson on 2/26/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import UIKit
import UserNotifications
import UserNotificationsUI
import Combine
import ParseCore

class NotificationViewController: UIViewController, UNNotificationContentExtension {

    private var cancellables = Set<AnyCancellable>()
    
    private var content: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Initialize Parse if necessary
        Config.shared.initializeParseIfNeeded()
    }
    
    func didReceive(_ notification: UNNotification) {
        guard let category
                = UserNotificationCategory(rawValue: notification.request.content.categoryIdentifier) else { return }

        switch category {
        case .connectionRequest:
            break
        case .connnectionConfirmed:
            break
        case .newMessage:
            break
        case .moment:
            
            self.preferredContentSize = CGSize(width: UIScreen.main.bounds.width,
                                               height: UIScreen.main.bounds.height * 0.7)
            self.view.setNeedsUpdateConstraints()
            self.view.setNeedsLayout()
            
            Task {
                guard let moment = try? await Moment.getObject(with: notification.momentId) else { return }
                let contentView = MomentContentView(with: moment)
                contentView.menuButton.isVisible = false 
                contentView.delegate = self
                    
                let actions = MomentAction.getActions(for: moment).compactMap({ momentAction in
                    return momentAction.action
                })
                self.extensionContext?.notificationActions = actions
                
                self.content = contentView
                self.view.addSubview(contentView)
            }
        }
    }

    func didReceive(_ response: UNNotificationResponse, completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        
        if let _ = MomentAction.init(rawValue: response.actionIdentifier) {
            completion(.dismissAndForwardAction)
        } else if let _ = UserNotificationAction.init(rawValue: response.actionIdentifier) {
            completion(.dismissAndForwardAction)
        } else {
            completion(.doNotDismiss)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if let first = self.view.subviews.first {
            first.expandToSuperviewSize()
        }
    }
}

extension NotificationViewController: MomentContentViewDelegate {
    
    func momentContentViewDidSelectCapture(_ view: MomentContentView) {
        
    }
    
    func momentContent(_ view: MomentContentView, didSelectPerson person: PersonType) {
        
    }
    
    func momentContent(_ view: MomentContentView, didSetCaption caption: String?) {
        self.view.layoutNow()
    }
}
