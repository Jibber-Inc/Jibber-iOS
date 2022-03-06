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
import Contacts
import StreamChat

/// A store that contains all people that the user has some relationship with. This could take the form of a directly connected Jibber chat user
/// or it could just be another person that has been invited but not yet joined Jibber.
class PeopleStore {

    static let shared = PeopleStore()

    // MARK: - Public Events
    @Published var personUpdated: PersonType?
    @Published var personDeleted: PersonType?

    var people: [PersonType] {
        var allPeople: [PersonType] = self.usersArray
        let contactPeople: [PersonType] = self.contactsArray.map { contact in
            return Person(withContact: contact)
        }
        allPeople.append(contentsOf: contactPeople)
        return allPeople
    }
    /// A dictionary of all the fetched users, keyed by their user id.
    private(set) var usersDictionary: [String : User] = [:] {
        didSet {
            guard self.usersDictionary != oldValue else { return }
            self.subscribeToUserUdpates()
        }
    }
    
    private var contactsDictionary: [String : CNContact] = [:]
    private var unclaimedReservations: [String : Reservation] = [:]
    var usersArray: [User] {
        return Array(self.usersDictionary.values)
    }
    var contactsArray: [CNContact] {
        return Array(self.contactsDictionary.values)
    }

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

            await self.getAndStoreAllContactsWithUnclaimedReservations()

            self.subscribeToConnectionUpdates()
        }

        // In the background, find existing Jibber users in the contacts.
        Task {
            await self.getAndStoreAllUsersThatAreContacts()
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
            
            var unfetchedUserIds = connections.compactMap { connection in
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
        } catch {
            logError(error)
        }
    }

    private func getAndStoreAllContactsWithUnclaimedReservations() async {
        let reservations = await Reservation.getAllUnclaimedWithContact()
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
        connectionSubscription.handleEvent { query, event in
            switch event {
            case .entered(let object), .created(let object):
                // When a new connection is made, add the connected user to the array.
                guard let connection = object as? Connection,
                      let nonMeUser = connection.nonMeUser else { break }

                self.usersDictionary[nonMeUser.personId] = nonMeUser
            case .updated(let object):
                // When a connection is updated, we update the corresponding user.
                guard let connection = object as? Connection,
                      let nonMeUser = connection.nonMeUser else { break }
                self.personUpdated = nonMeUser

                self.usersDictionary[nonMeUser.personId] = nonMeUser
            case .left(let object), .deleted(let object):
                // Remove users when their connections are deleted.
                guard let connection = object as? Connection,
                      let nonMeUser = connection.nonMeUser else { break }

                self.usersDictionary[nonMeUser.personId] = nil
                self.personDeleted = nonMeUser
            }
        }

        // Observe changes to all unclaimed reservations that the user owns.
        let reservationQuery = Reservation.allUnclaimedWithContactQuery()
        let reservationSubscription = Client.shared.subscribe(reservationQuery)
        reservationSubscription.handleEvent { query, event in
            switch event {
            case .entered(let object), .created(let object), .updated(let object):
                guard let reservation = object as? Reservation,
                      let contactId = reservation.contactId else { return }

                self.unclaimedReservations[reservation.objectId!] = reservation

                guard ContactsManager.shared.hasPermissions, let contact =
                        ContactsManager.shared.searchForContact(with: .identifier(contactId)).first else {
                            return
                        }
                self.contactsDictionary[contactId] = contact
            case .left(let object), .deleted(let object):
                guard let reservation = object as? Reservation,
                      let contactId = reservation.contactId else { return }

                self.contactsDictionary[contactId] = nil
                self.unclaimedReservations[reservation.objectId!] = nil

                guard let contact =
                        ContactsManager.shared.searchForContact(with: .identifier(contactId)).first else {
                            return
                        }
                self.personDeleted = contact
            }
        }
    }
    
    private func subscribeToUserUdpates() {
        guard let query = User.query() else { return }
        Client.shared.unsubscribe(query)

        var connectedUsersObjectIds = self.usersArray.compactMap { user in
            return user.objectId
        }
        
        connectedUsersObjectIds.append(User.current()!.objectId!)
        
        query.whereKey("objectId", containedIn: connectedUsersObjectIds)
        query.includeKey("latestContextCue")
        let subscription = Client.shared.subscribe(query)
        subscription.handleEvent { query, event in
            switch event {
            case .updated(let object):
                guard let user = object as? User else { return }
                self.personUpdated = user
            default:
                break
            }
        }
    }

    // MARK: - Helper functions

    func getPeople(for conversation: ChatChannel) async -> [PersonType] {
        var people: [PersonType] = []
        let nonMeMembers = conversation.lastActiveMembers.filter { member in
            return member.id != User.current()?.objectId
        }
        await nonMeMembers.userIDs.asyncForEach { userId in
            guard let person = await self.getPerson(withPersonId: userId) else { return }
            people.append(person)
        }

        await self.unclaimedReservations.asyncForEach { (reservationId, reservation) in
            guard reservation.conversationCid == conversation.cid.description,
                    let contactId = reservation.contactId else { return }

            guard let person = await self.getPerson(withPersonId: contactId) else { return }
            people.append(person)
        }
        
        return people
    }

    func getPerson(withPersonId personId: String) async -> PersonType? {
        var foundPerson: PersonType? = nil

        if let user = self.usersDictionary[personId] {
            foundPerson = user
        } else if let contact = self.contactsDictionary[personId] {
            foundPerson = contact
        } else if let user = try? await User.getObject(with: personId) {
            foundPerson = user

            // This is a newly retrieved person, so cache it and let subscribers know about it.
            self.usersDictionary[user.personId] = user
            self.personUpdated = user
        }
        
        return foundPerson
    }
}
