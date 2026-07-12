//
//  NoticeStore.swift
//  Jibber
//
//  Created by Benji Dodgson on 4/1/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import ParseCore
import JibberParseLiveQuery
import Localization

/// Carries one legacy Parse object from the LiveQuery callback to the main actor.
private struct NoticeLiveQueryTransfer: @unchecked Sendable {
    enum Change: Sendable {
        case added
        case updated
        case removed
    }

    let change: Change
    let notice: Notice
}

@MainActor
final class NoticeStore {

    static let shared = NoticeStore()
    
    @Published private(set) var notices: [SystemNotice] = []
    
    private var __notices: [SystemNotice] = [] {
        didSet {
            self.notices = self.__notices.filter({ notice in
                return notice.type != .unreadMessages &&
                notice.type != .unknown &&
                notice.type != .messageRead
            }).sorted()
        }
    }

    private var initializeTask: Task<Void, Error>?

    private lazy var liveQueryRelay = OrderedMainActorEventRelay<NoticeLiveQueryTransfer> { [weak self] transfer in
        guard let self else { return }

        switch transfer.change {
        case .added:
            if !self.__notices.contains(where: { existing in
                existing.notice?.objectId == transfer.notice.objectId
            }) {
                self.__notices.append(SystemNotice(with: transfer.notice))
            }

        case .updated:
            if let first = self.__notices.first(where: { existing in
                existing.notice?.objectId == transfer.notice.objectId
            }) {
                self.__notices.remove(object: first)
            }
            self.__notices.append(SystemNotice(with: transfer.notice))

        case .removed:
            if let first = self.__notices.first(where: { existing in
                existing.notice?.objectId == transfer.notice.objectId
            }) {
                self.__notices.remove(object: first)
            }
        }
    }

    func initializeIfNeeded() async throws {
        // If we already have an initialization task, wait for it to finish.
        if let initializeTask = self.initializeTask {
            try await initializeTask.value
            return
        }

        // Otherwise start a new initialization task and wait for it to finish.
        self.initializeTask = Task {
            // Get all of the notices.
            self.__notices = try await Notice.fetchAll().compactMap({ notice in
                return SystemNotice(with: notice)
            })
            
            self.subscribeToUpdates()
        }

        do {
            try await self.initializeTask?.value
        } catch {
            // Dispose of the task because it failed, then pass the error along.
            self.initializeTask = nil
            throw error
        }
    }
    
    func delete(notice: SystemNotice) {
        self.__notices.remove(object: notice)
        
        if let n = notice.notice {
            do {
                try n.delete()
            } catch {
                logError(error)
            }
        }
    }
    
    func removeNoticeIfNeccessary(for message: Messageable) {
        guard message.deliveryType == .timeSensitive else { return }
        
        guard let first = self.__notices.first(where: { notice in
            if notice.type == .timeSensitiveMessage,
                let msgId = notice.attributes?["messageId"] as? String,
                msgId == message.id {
                return true
            } else {
                return false
            }
        }) else { return }
        
        self.delete(notice: first)
    }
    
    private func subscribeToUpdates() {
        Client.shared.shouldPrintWebSocketLog = false

        // Query for all notices related to the user.
        let query = Notice.query()!
        let subscription = Client.shared.subscribe(query)
        let liveQueryRelay = self.liveQueryRelay
        subscription.handleEvent { _, event in
            let transfer: NoticeLiveQueryTransfer

            switch event {
            case .entered(let object), .created(let object):
                guard let notice = object as? Notice else { return }
                transfer = NoticeLiveQueryTransfer(change: .added, notice: notice)

            case .updated(let object):
                guard let notice = object as? Notice else { return }
                transfer = NoticeLiveQueryTransfer(change: .updated, notice: notice)

            case .left(let object), .deleted(let object):
                guard let notice = object as? Notice else { return }
                transfer = NoticeLiveQueryTransfer(change: .removed, notice: notice)
            }

            liveQueryRelay.send(transfer)
        }
    }
}
