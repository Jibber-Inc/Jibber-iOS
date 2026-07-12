//
//  MomentAction.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/11/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

enum MomentAction: String, CaseIterable {
    
    case view = "moment.view"
    case record = "moment.record"
    case comment = "moment.comment"
    
    var text: String {
        switch self {
        case .view:
            return "View"
        case .record:
            return "Record"
        case .comment:
            return "Comment"
        }
    }
    
    var target: DeepLinkTarget {
        switch self {
        case .view:
            return .moment
        case .record:
            return .capture
        case .comment:
            return .comment
        }
    }
    
    var action: UNNotificationAction? {
        let icon: UNNotificationActionIcon
        
        switch self {
        case .view:
            icon = UNNotificationActionIcon(systemImageName: ImageSymbol.eye.rawValue)
        case .record:
            icon = UNNotificationActionIcon(systemImageName: ImageSymbol.recordingTape.rawValue)
        case .comment:
            icon = UNNotificationActionIcon(systemImageName: ImageSymbol.pencil.rawValue)
        }
        
        return UNNotificationAction(identifier: self.rawValue,
                                    title: self.text,
                                    options: .foreground,
                                    icon: icon)
    }
    
    @MainActor
    static func getActions(for moment: Moment) -> [MomentAction] {
        guard !moment.isFromCurrentUser else { return [] }
        
        if moment.isAvailable {
            return [.view, .comment]
        } else {
            return [.record]
        }
    }
}
