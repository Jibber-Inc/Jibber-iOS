//
//  UserStore.swift
//  Jibber
//
//  Created by Benji Dodgson on 10/22/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import ParseLiveQuery
import Parse
import StreamChat

/// A store that contains all people that the user has some relationship with. This could take the form of a directly connected Jibber chat user
/// or it could just be another person that has been invited but not yet joined Jibber.
class PersonStore {

    static let shared = PersonStore()
    private var cancellables = Set<AnyCancellable>()

    @Published var userUpdated: User?
    @Published var userDeleted: User?

    private(set) var users: [User] = []
    private(set) var personTypes: [PersonType] = []

    private var initializeTask: Task<Void, Never>?

    func initializeIfNeeded() async {
        // If we already have an initialization task, wait for it to finish.
        if let initializeTask = self.initializeTask {
            await initializeTask.value
            return
        }

        // Otherwise start a new initialization task and wait for it to finish.
        self.initializeTask = Task {
            // Get all of the connections and unclaimed reservations.
            await self.getAndStoreAllConnectedUsers()

            // Include the current user.
            if let current = User.current() {
                self.personTypes.append(current)
            }

            await self.getAndStoreAllContactsWithUnclaimedReservations()

            self.subscribeToUpdates()
        }

        await self.initializeTask?.value
    }

    private func getAndStoreAllConnectedUsers() async {
        do {
            let connections = try await GetAllConnections().makeRequest(andUpdate: [],
                                                                        viewsToIgnore: [])
                .filter { (connection) -> Bool in
                    return !connection.nonMeUser.isNil
                }
            connections.forEach { connection in
                guard let nonMeUser = connection.nonMeUser else { return }
                self.personTypes.append(nonMeUser)
            }
        } catch {
            logError(error)
        }
    }

    private func getAndStoreAllContactsWithUnclaimedReservations() async {
        let reservations = await Reservation.getAllUnclaimed()
        reservations.forEach { reservation in
            guard let contactId = reservation.contactId else { return }
            guard let contact =
                    ContactsManger.shared.searchForContact(with: .identifier(contactId)).first else {
                        return
                    }
            let person = Person(withContact: contact)
            self.personTypes.append(person)
        }
    }

    private func subscribeToUpdates() {
        Client.shared.shouldPrintWebSocketLog = false

        // Query for all connections related to the user. Either sent to OR from.
        let toQuery = Connection.query()!.whereKey("to", equalTo: User.current()!)
        let fromQuery = Connection.query()!.whereKey("from", equalTo: User.current()!)
        let orQuery = PFQuery.orQuery(withSubqueries: [toQuery, fromQuery])
        let connectionSubscription = Client.shared.subscribe(orQuery)
        connectionSubscription.handleEvent { query, event in
            switch event {
            case .entered(let object), .created(let object):
                guard let connection = object as? Connection,
                      let nonMeUser = connection.nonMeUser else { break }

                self.personTypes.append(nonMeUser)
            case .updated(let object):
                guard let connection = object as? Connection,
                      let nonMeUser = connection.nonMeUser else { break }
                self.userUpdated = nonMeUser

                if let indexToUpdate = self.personTypes.firstIndex(where: { personType in
                    return personType.fullName == nonMeUser.fullName
                }) {
                    self.personTypes[indexToUpdate] = nonMeUser
                }

            case .left(let object), .deleted(let object):
                guard let connection = object as? Connection,
                      let nonMeUser = connection.nonMeUser else { break }

                self.personTypes.removeAll { personType in
                    return personType.fullName == nonMeUser.fullName
                }
                self.userDeleted = nonMeUser
            }
        }
        
        let reservationQuery = Reservation.query()!
        reservationQuery.whereKey(ReservationKey.createdBy.rawValue, equalTo: User.current()!)
        reservationQuery.whereKey(ReservationKey.isClaimed.rawValue, equalTo: false)
        let reservationSubscription = Client.shared.subscribe(reservationQuery)
        reservationSubscription.handleEvent { query, event in
            // TODO: handle the event
        }
    }

    // MARK: - Helper functions

    func mapMembersToUsers(members: [ConversationMember]) async throws -> [User] {
        var users: [User] = []
        await members.userIDs.asyncForEach { userId in
            if let user = await self.findUser(with: userId) {
                users.append(user)
            }
        }
        
        return users
    }
    
    func findUser(with objectID: String) async -> User? {
        var foundUser: User? = nil

        if let user = PersonStore.shared.users.first(where: { user in
            return user.objectId == objectID
        }) {
            foundUser = user
        } else if let user = try? await User.getObject(with: objectID) {
            foundUser = user
        }
        
        return foundUser
    }
}
