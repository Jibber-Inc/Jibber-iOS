//
//  MomentStore.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/10/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import MessagingContracts
import Combine
import ParseCore
import JibberParseLiveQuery
import Localization

/// Carries one legacy Parse object from the LiveQuery callback to the main actor.
private struct MomentLiveQueryTransfer: @unchecked Sendable {
    enum Change: Sendable {
        case added
        case updated
        case removed
    }

    let change: Change
    let moment: Moment
}

@MainActor
class MomentsStore {

    static let shared = MomentsStore()
    
    @Published private(set) var todaysMoments: [Moment] = []
    
    var hasRecordedToday: Bool {
        return self.todaysMoments.first { moment in
            moment.author == User.current()
        }.exists
    }
    
    private var __moments: [Moment] = [] {
        didSet {
            self.todaysMoments = self.__moments
        }
    }

    private var initializeTask: Task<Void, Error>?
    private var cancellables = Set<AnyCancellable>()

    private lazy var liveQueryRelay = OrderedMainActorEventRelay<MomentLiveQueryTransfer> { [weak self] transfer in
        guard let self else { return }

        switch transfer.change {
        case .added:
            if !self.__moments.contains(where: { existing in
                existing.objectId == transfer.moment.objectId
            }) {
                self.__moments.append(transfer.moment)
            }

        case .updated:
            if let first = self.__moments.first(where: { existing in
                existing.objectId == transfer.moment.objectId
            }) {
                self.__moments.remove(object: first)
            }
            self.__moments.append(transfer.moment)

        case .removed:
            if let first = self.__moments.first(where: { existing in
                existing.objectId == transfer.moment.objectId
            }) {
                self.__moments.remove(object: first)
            }
        }
    }
    
    //MARK: PUBLIC

    func initializeIfNeeded() async throws {
        // If we already have an initialization task, wait for it to finish.
        if let initializeTask = self.initializeTask {
            try await initializeTask.value
            return
        }

        // Otherwise start a new initialization task and wait for it to finish.
        self.initializeTask = Task {
            // Get all of todays moments.
            self.__moments = try await self.fetchAllOfTodaysMoments()
            
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
        
    func getTodaysMoment(withPersonId personId: String) async -> Moment? {
        try? await self.initializeIfNeeded()
        return self.todaysMoments.first { moment in
            return moment.author?.objectId == personId
        }
    }
    
    func getAll(for person: PersonType) async throws -> [Moment] {
        return try await withCheckedThrowingContinuation { continuation in
            if let query = Moment.query(),
                let user = person as? User {
                
                query.whereKey("author", equalTo: user)
                query.includeKey("preview")
                query.findObjectsInBackground { objects, error in
                    if let moments = objects as? [Moment] {
                        continuation.resume(returning: moments)
                    } else if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: ClientError.apiError(detail: "Failed to retrieve moments"))
                    }
                }
            } else {
                continuation.resume(throwing: ClientError.apiError(detail: "No query for Moments"))
            }
        }
    }
    
    func getLast14DaysMoments(for person: PersonType) async throws -> [Moment] {
        return try await withCheckedThrowingContinuation { continuation in
            if let query = Moment.query(),
                let user = person as? User,
                let daysAgoDate = Date.today.subtract(component: .day, amount: 14) {
                
                query.whereKey("author", equalTo: user)
                query.includeKey("expression")
                query.includeKey("preview")
                query.whereKey("createdAt", greaterThan: daysAgoDate)
                query.findObjectsInBackground { objects, error in
                    if let moments = objects as? [Moment] {
                        continuation.resume(returning: moments)
                    } else if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: ClientError.apiError(detail: "Failed to retrieve moments"))
                    }
                }
            } else {
                continuation.resume(throwing: ClientError.apiError(detail: "No query for Moments"))
            }
        }
    }
    
    #if IOS
    @discardableResult
    func createMoment(from recording: PiPRecording,
                      location: CLLocation?,
                      caption: String?) async throws -> Moment {
        
        guard let expressionURL = recording.frontRecordingURL,
               let momentURL = recording.backRecordingURL,
              let previewURL = recording.previewURL else { throw ClientError.message(detail: "Missing moment recorded media") }
        
        try await self.initializeIfNeeded()
        
        guard !self.hasRecordedToday else { throw ClientError.message(detail: "Moment for today already created.") }
        
        let expressionData = try Data(contentsOf: expressionURL)
        let momentData = try Data(contentsOf: momentURL)
        let previewData = try Data(contentsOf: previewURL)

        let expression = Expression()

        expression.author = User.current()
        expression.file = PFFileObject(name: "expression.mov", data: expressionData)
        expression.emojiString = nil

        let savedExpression = try await expression.saveToServer()

        let moment = Moment()
        moment.expression = savedExpression
        moment.author = User.current()
        moment.file = PFFileObject(name: "moment.mov", data: momentData)
        moment.preview = PFFileObject(name: "preview.mov", data: previewData)
        moment.caption = caption ?? "No caption"
        moment.location = PFGeoPoint(location: location)

        let savedMoment = try await moment.saveToServer()
        guard let momentID = savedMoment.objectId else {
            throw ClientError.message(detail: "Saved moment is missing its object ID.")
        }
        guard let authorID = savedMoment.author?.objectId else {
            throw ClientError.message(detail: "Saved moment is missing its author ID.")
        }

        // A Moment only receives its canonical identity after Parse saves it.
        // Reusing that identity for both keys makes retries recover the same
        // conversation even if the final Moment-link save was interrupted.
        let conversationKey = "moment:\(momentID)"
        let conversation = try await ParseMessagingManager.shared.createConversation(
            memberIDs: [authorID],
            type: .moment,
            clientConversationID: conversationKey,
            contextKey: conversationKey
        )

        savedMoment.messagingConversationId = conversation.id
        let linkedMoment = try await savedMoment.saveToServer()
        self.__moments.append(linkedMoment)

        return linkedMoment
    }
    #endif 
    
    //MARK: PRIVATE
    
    private func fetchAllOfTodaysMoments() async throws -> [Moment] {
        try await PeopleStore.shared.initializeIfNeeded()
        
        var allPeople: [User] = PeopleStore.shared.allConnections
            .filter({ connection in
                return connection.status == .accepted
            })
            .compactMap { connection in
            return connection.nonMeUser
        }
        
        allPeople.insert(User.current()!, at: 0)
                
        return try await withCheckedThrowingContinuation { continuation in
            if let query = Moment.query() {
                query.whereKey("author", containedIn: allPeople)
                query.includeKey("expression")
                query.includeKey("preview")
                query.whereKey("createdAt", greaterThan: Date.today)
                query.findObjectsInBackground { objects, error in
                    if let moments = objects as? [Moment] {
                        continuation.resume(returning: moments)
                    } else if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: ClientError.apiError(detail: "Failed to retrieve moments"))
                    }
                }
            } else {
                continuation.resume(throwing: ClientError.apiError(detail: "No query for Moments"))
            }
        }
    }
    
    private func subscribeToUpdates() {
        
        // Keep track of app foreground events so we can be sure its the same day.
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification).mainSink { [weak self] _ in
            guard let self else { return }
            
            Task { [weak self] in
                guard let self else { return }

                do {
                    self.__moments = try await self.fetchAllOfTodaysMoments()
                } catch {
                    logError(error)
                }
            }
        }.store(in: &self.cancellables)
        
        Client.shared.shouldPrintWebSocketLog = false

        // Query for all of todays moments.
        let query = Moment.query()!
        let subscription = Client.shared.subscribe(query)
        let liveQueryRelay = self.liveQueryRelay
        subscription.handleEvent { _, event in
            let transfer: MomentLiveQueryTransfer

            switch event {
            case .entered(let object), .created(let object):
                guard let moment = object as? Moment else { return }
                transfer = MomentLiveQueryTransfer(change: .added, moment: moment)

            case .updated(let object):
                guard let moment = object as? Moment else { return }
                transfer = MomentLiveQueryTransfer(change: .updated, moment: moment)

            case .left(let object), .deleted(let object):
                guard let moment = object as? Moment else { return }
                transfer = MomentLiveQueryTransfer(change: .removed, moment: moment)
            }

            liveQueryRelay.send(transfer)
        }
    }
}
