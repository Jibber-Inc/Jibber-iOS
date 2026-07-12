//
//  SystemNotice.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/31/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

protocol Noticeable: Hashable {
    var notice: Notice? { get set }
    var created: Date { get set }
    var priority: Int { get set }
    var attributes: [String: AnyHashable]? { get set }
}

/// Notice snapshots are treated as immutable while used as diffable identifiers.
/// Parse's legacy Objective-C notice object is already marked unchecked Sendable.
struct SystemNotice: Noticeable, Comparable, @unchecked Sendable {

    var notice: Notice?
    var type: Notice.NoticeType
    var created: Date
    var priority: Int = 0
    var attributes: [String : AnyHashable]?

    init(createdAt: Date?,
         notice: Notice?,
         type: Notice.NoticeType,
         priority: Int,
         attributes: [String: AnyHashable]?) {

        self.created = createdAt ?? Date()
        self.notice = notice
        self.attributes = attributes
        self.priority = priority
        self.type = type
    }

    init(with notice: Notice) {

        self.init(createdAt: notice.createdAt,
                  notice: notice,
                  type: notice.type,
                  priority: notice.priority,
                  attributes: notice.attributes)
    }

    init(withConneciton connection: Connection) {
        self.init(createdAt: connection.createdAt,
                  notice: nil,
                  type: .connectionRequest,
                  priority: 1,
                  attributes: ["connectionId": connection.objectId!])
    }

    static func == (lhs: SystemNotice, rhs: SystemNotice) -> Bool {
        return lhs.notice == rhs.notice &&
            lhs.type == rhs.type &&
            lhs.priority == rhs.priority &&
            lhs.created == rhs.created
    }

    static func < (lhs: SystemNotice, rhs: SystemNotice) -> Bool {
        return lhs.created > rhs.created 
    }
}
