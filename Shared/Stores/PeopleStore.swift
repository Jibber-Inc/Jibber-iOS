//
//  UserStore.swift
//  Jibber
//
//  Created by Benji Dodgson on 10/22/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import ParseCore
import JibberParseLiveQuery
import Contacts

/// Carries one legacy Parse object from a LiveQuery callback to the main actor.
private struct ConnectionLiveQueryTransfer: @unchecked Sendable {
    enum Change: Sendable {
        case added
        case updated
        case removed
    }

    let change: Change
    let connection: Connection
}

/// Carries one legacy Parse object from a LiveQuery callback to the main actor.
private struct ReservationLiveQueryTransfer: @unchecked Sendable {
    enum Change: Sendable {
        case upserted
        case removed
    }

    let change: Change
    let reservation: Reservation
}

/// Carries one legacy Parse object from a LiveQuery callback to the main actor.
private struct UserLiveQueryTransfer: @unchecked Sendable {
    let user: User
}

/// A store that contains all people that the user has some relationship with. This could take the form of a directly connected Jibber chat user
/// or it could just be another person that has been invited but not yet joined Jibber.
@MainActor
class PeopleStore {

    static let shared = PeopleStore()

    // MARK: - Public Events
    @Published var personUpdated: PersonType?
    @Published var personDeleted: PersonType?
    @Published var personAdded: PersonType?

    var people: [PersonType] {
        var allPeople: [PersonType] = self.usersArray
        let contactPeople: [PersonType] = self.contactsArray.map { contact in
            return Person(withContact: contact)
        }
        allPeople.append(contentsOf: contactPeople)
        return allPeople
    }
    
    var connectedPeople: [PersonType] {
        let allConnectionIds = self.allConnections.compactMap { connection in
            return connection.nonMeUser?.objectId
        }
        
        return self.people.filter { person in
            return allConnectionIds.contains(person.personId)
        }
    }
    
    /// A dictionary of all the fetched users, keyed by their user id.
    private(set) var usersDictionary: [String : User] = [:] {
        didSet {
            guard self.usersDictionary != oldValue else { return }
            self.subscribeToUserUpdates()
        }
    }
    
    private var contactsDictionary: [String : CNContact] = [:]
    
    var sortedUnclaimedReservationWithoutContact: [Reservation] {
        return Array(self.unclaimedReservationWithoutContact.values).sorted { lhs, rhs in
            guard let lhsDate = lhs.createdAt, let rhsDate = rhs.createdAt else { return false }
            return lhsDate > rhsDate
        }
    }
    
    var unclaimedReservationWithoutContact: [String: Reservation] {
        return self.unclaimedReservations.filter { key in
            return key.value.isClaimed == false && key.value.contactId.isNil
        }
    }
    
    var unclaimedReservationWithContact: [String: Reservation] {
        return self.unclaimedReservations.filter { key in
            return key.value.isClaimed == false && key.value.contactId.exists
        }
    }
    
    private(set) var unclaimedReservations: [String : Reservation] = [:]
    
    var usersArray: [User] {
        return Array(self.usersDictionary.values)
    }
    var contactsArray: [CNContact] {
        return Array(self.contactsDictionary.values)
    }
    
    private(set) var allConnections: [Connection] = []

    private var initializeTask: Task<Void, Error>?

    private lazy var connectionEventRelay = OrderedMainActorEventRelay<ConnectionLiveQueryTransfer> { [weak self] transfer in
        guard let self,
              let nonMeUser = transfer.connection.nonMeUser else { return }

        switch transfer.change {
        case .added:
            if !self.allConnections.contains(where: { existing in
                existing.objectId == transfer.connection.objectId
            }) {
                self.allConnections.append(transfer.connection)
            }
            self.personAdded = nonMeUser
            self.usersDictionary[nonMeUser.personId] = nonMeUser

        case .updated:
            self.personUpdated = nonMeUser
            if let first = self.allConnections.first(where: { existing in
                existing.objectId == transfer.connection.objectId
            }) {
                self.allConnections.remove(object: first)
            }
            self.allConnections.append(transfer.connection)
            self.usersDictionary[nonMeUser.personId] = nonMeUser

        case .removed:
            self.allConnections.remove(object: transfer.connection)
            self.usersDictionary[nonMeUser.personId] = nil
            self.personDeleted = nonMeUser
        }
    }

    private lazy var reservationEventRelay = OrderedMainActorEventRelay<ReservationLiveQueryTransfer> { [weak self] transfer in
        guard let self,
              let reservationId = transfer.reservation.objectId else { return }

        switch transfer.change {
        case .upserted:
            self.unclaimedReservations[reservationId] = transfer.reservation
            guard let contactId = transfer.reservation.contactId,
                  ContactsManager.shared.hasPermissions,
                  let contact = ContactsManager.shared.searchForContact(with: .identifier(contactId)).first else {
                return
            }
            self.contactsDictionary[contactId] = contact

        case .removed:
            self.unclaimedReservations[reservationId] = nil
            guard let contactId = transfer.reservation.contactId else { return }
            self.contactsDictionary[contactId] = nil
            guard let contact = ContactsManager.shared
                .searchForContact(with: .identifier(contactId)).first else { return }
            self.personDeleted = contact
        }
    }

    private lazy var userEventRelay = OrderedMainActorEventRelay<UserLiveQueryTransfer> { [weak self] transfer in
        self?.personUpdated = transfer.user
    }

    func initializeIfNeeded() async throws {
        // If we already have an initialization task, wait for it to finish.
        if let initializeTask = self.initializeTask {
            try await initializeTask.value
            return
        }

        // Otherwise start a new initialization task and wait for it to finish.
        self.initializeTask = Task {
            // Get all of the connections and unclaimed reservations.
            try await self.getAndStoreAllConnectedUsers()

            await self.getAndStoreAllContactsWithUnclaimedReservations()

            self.subscribeToConnectionUpdates()
        }

        // In the background, find existing Jibber users in the contacts.
        Task {
            await self.getAndStoreAllUsersThatAreContacts()
        }

        do {
            try await self.initializeTask?.value
        } catch {
            // Dispose of the task because it failed, then pass the error along.
            self.initializeTask = nil
            throw error
        }
    }
    
    private func getAndStoreAllConnectedUsers() async throws {
        self.allConnections = try await GetAllConnections().makeRequest(andUpdate: [],
                                                                    viewsToIgnore: [])
            .filter { (connection) -> Bool in
                return !connection.nonMeUser.isNil
            }
        
        var unfetchedUserIds = self.allConnections.compactMap { connection in
            return connection.nonMeUser?.objectId
        }

        if let current = User.current()?.objectId {
            unfetchedUserIds.append(current)
        }

        if let users = try? await User.fetchAndUpdateLocalContainer(where: unfetchedUserIds,
                                                                         container: .users) {
            users.forEach { user in
                self.usersDictionary[user.personId] = user
            }
        }
    }

    private func getAndStoreAllContactsWithUnclaimedReservations() async {
        let reservations = await Reservation.getAllUnclaimed()
        reservations.forEach { reservation in
            if let reservationId = reservation.objectId {
                self.unclaimedReservations[reservationId] = reservation
            }

            guard let contactId = reservation.contactId else { return }
            guard ContactsManager.shared.hasPermissions, let contact =
                    ContactsManager.shared.searchForContact(with: .identifier(contactId)).first else {
                        return
                    }
            self.contactsDictionary[contactId] = contact
        }
    }

    private func getAndStoreAllUsersThatAreContacts() async {
        guard ContactsManager.shared.hasPermissions else { return }

        // Get every single parse user and check to see if they exist in the user's contacts.
        // If they do, then store them in the user array.
        // TODO: Do this more efficiently.
        let userQuery = User.query()!
        let usersObjects = (try? await userQuery.findObjectsInBackground()) ?? []

        let contacts = await ContactsManager.shared.fetchContacts()

        for userObject in usersObjects {
            guard let user = userObject as? User, !user.isCurrentUser else { continue }

            if contacts.contains(where: { contact in
                guard let contactPhone = contact.findBestPhoneNumberString(),
                      let userPhone = user.phoneNumber?.removeAllNonNumbers() else { return false }

                return FuzzyPhoneNumber(contactPhone) == FuzzyPhoneNumber(userPhone)
            }) {
                self.usersDictionary[user.personId] = user
            }
        }
    }

    private func subscribeToConnectionUpdates() {
        Client.shared.shouldPrintWebSocketLog = false

        // Query for all connections related to the user. Either sent to OR from.
        let toQuery = Connection.query()!.whereKey("to", equalTo: User.current()!)
        let fromQuery = Connection.query()!.whereKey("from", equalTo: User.current()!)
        let orQuery = PFQuery.orQuery(withSubqueries: [toQuery, fromQuery])
        let connectionSubscription = Client.shared.subscribe(orQuery)
        let connectionEventRelay = self.connectionEventRelay
        connectionSubscription.handleEvent { _, event in
            let transfer: ConnectionLiveQueryTransfer

            switch event {
            case .entered(let object), .created(let object):
                guard let connection = object as? Connection else { return }
                transfer = ConnectionLiveQueryTransfer(change: .added, connection: connection)

            case .updated(let object):
                guard let connection = object as? Connection else { return }
                transfer = ConnectionLiveQueryTransfer(change: .updated, connection: connection)

            case .left(let object), .deleted(let object):
                guard let connection = object as? Connection else { return }
                transfer = ConnectionLiveQueryTransfer(change: .removed, connection: connection)
            }

            connectionEventRelay.send(transfer)
        }

        // Observe changes to all unclaimed reservations that the user owns.
        let reservationQuery = Reservation.allUnclaimedQuery()
        let reservationSubscription = Client.shared.subscribe(reservationQuery)
        let reservationEventRelay = self.reservationEventRelay
        reservationSubscription.handleEvent { _, event in
            let transfer: ReservationLiveQueryTransfer

            switch event {
            case .entered(let object), .created(let object), .updated(let object):
                guard let reservation = object as? Reservation else { return }
                transfer = ReservationLiveQueryTransfer(change: .upserted, reservation: reservation)

            case .left(let object), .deleted(let object):
                guard let reservation = object as? Reservation else { return }
                transfer = ReservationLiveQueryTransfer(change: .removed, reservation: reservation)
            }

            reservationEventRelay.send(transfer)
        }
    }
    
    private func subscribeToUserUpdates() {
        guard let query = User.query() else { return }
        Client.shared.unsubscribe(query)

        var connectedUsersObjectIds = self.usersArray.compactMap { user in
            return user.objectId
        }
        
        connectedUsersObjectIds.append(User.current()!.objectId!)
        
        query.whereKey("objectId", containedIn: connectedUsersObjectIds)
        query.includeKey("latestContextCue")
        let subscription = Client.shared.subscribe(query)
        let userEventRelay = self.userEventRelay
        subscription.handleEvent { _, event in
            switch event {
            case .updated(let object):
                guard let user = object as? User else { return }
                let transfer = UserLiveQueryTransfer(user: user)

                userEventRelay.send(transfer)
            default:
                break
            }
        }
    }

    // MARK: - Helper functions

    func getPerson(withPersonId personId: String) async -> PersonType? {
        var foundPerson: PersonType? = nil

        if let user = self.usersDictionary[personId], let updated = try? await user.retrieveDataIfNeeded() {
            foundPerson = updated
        } else if let contact = self.contactsDictionary[personId] {
            foundPerson = contact
        } else if let user = try? await User.getObject(with: personId).retrieveDataIfNeeded() {
            foundPerson = user

            // This is a newly retrieved person, so cache it and let subscribers know about it.
            self.usersDictionary[user.personId] = user
            self.personUpdated = user
        }
        
        return foundPerson
    }
}
