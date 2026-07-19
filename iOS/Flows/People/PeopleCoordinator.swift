//
//  PeopleCoordinator.swift
//  Benji
//
//  Created by Benji Dodgson on 10/5/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import Contacts
import ContactsUI
import Localization
import ParseCore

class PeopleCoordinator: PresentableCoordinator<[Person]> {

    private lazy var peopleNavController = PeopleNavigationController(showConnections: self.selectedConversationId.exists)
    private var shareContinuation: CheckedContinuation<Void, Never>?
    private var sharedPerson: Person?
    private var invitationRequestIds: [String: String] = [:]
    var selectedReservation: Reservation?

    var peopleToInvite: [Person] {
        return self.peopleNavController.peopleVC.selectedPeople
    }
    var reservations: [Reservation] {
        return self.peopleNavController.peopleVC.reservations
    }

    private var inviteIndex: Int = 0

    /// People who were selected for invitation/connection during this flow.
    private(set) var invitedPeople: [Person] = []
    
    var selectedConversationId: String?

    override func toPresentable() -> DismissableVC {
        return self.peopleNavController
    }

    override func start() {
        super.start()
        
        self.peopleNavController.peopleVC.button.didSelect { [unowned self] in
            self.peopleNavController.prepareForInvitations()
            
            Task {
                await self.inviteRemainingPeople()
            }.add(to: self.taskPool)
        }
    }
}

extension PeopleCoordinator {

    /// Invites the next person in the array of people to invite and keeps doing so until there are no more people to invite.
    /// Once there are no more people to invite, the finishInviting phase is called.
    @MainActor
    func inviteRemainingPeople() async {
        // If there are no more people to invite, then finish the flow.
        guard var person = self.peopleToInvite[safe: self.inviteIndex] else {
            await self.finishInviting()
            return
        }

        guard !Task.isCancelled else { return }

        self.inviteIndex += 1

        // If the invited person is already connected, there's no need to formally invite them.
        // Move on to the next person
        if let connection = try? await person.connection?.retrieveDataIfNeeded(),
            connection.status == .accepted {
            // Do nothing because the person is already connected.
        } else {
            // The person is not connected, we'll need to try inviting them to connect.
            if let connection = await self.invite(person: person) {
                // If a connection was made, update the person's connection info.
                person.connection = connection
            }
        }

        // Keep track of who was connected/invited.
        self.invitedPeople.append(person)

        // Continue inviting the rest of the people.
        await self.inviteRemainingPeople()
    }

    func invite(person: Person) async -> Connection? {
        
        await self.peopleNavController.peopleVC.showLoading(for: person)

        // You can't invite a person without a phone number.
        guard let phoneNumber = person.phoneNumber else { return nil }

        // If the user already has an account, we can just connect with them directly.
        if let user = await self.findUser(withPhoneNumber: phoneNumber) {
            return await self.presentConnectionFlow(for: user)
        } else if let contact = person.cnContact {
            
            // Allocate or reuse an invitation idempotently, then present the
            // rich system share sheet so Messages can render our contextual
            // LinkPresentation metadata.
            await self.shareInvitation(
                with: person,
                contact: contact,
                preferredReservation: self.getReservation(for: contact)
            )
        }

        return nil
    }

    /// Returns the reservation that should be used to invite this person. Nil is returned if there are no valid reservation objects left that can be used.
    private func getReservation(for contact: CNContact) -> Reservation? {
        let contactId = contact.identifier

        // First check to see if there's already a reservation object associated with this contact.
        if let existingReservation = self.reservations.first(where: { reservation in
            return reservation.contactId == contactId
        }) {
            return existingReservation
        }

        // If there are no reservations associated with the contact, then return an unused reservation.
        return self.reservations.first { reservation in
            return reservation.contactId == nil
        }
    }

    // MARK: - Existing Users Flow

    /// Returns a Jibber user that has the same phone number as the passed in contact.
    private func findUser(withPhoneNumber phone: String) async -> User? {
        // Search for a user with phone number
        return try? await User.getFirstObject(where: "phoneNumber", contains: phone)
    }

    /// Presents an alert that asks if the user wants to connect with the passed in user. Finishes once a connection is made or the user cancels.
    func presentConnectionFlow(for user: User) async -> Connection? {
        
        return await withCheckedContinuation { continuation in
            self.removeChild()

            let coordinator = PersonConnectionCoordinator(with: user,
                                                          router: self.router,
                                                          deepLink: self.deepLink)

            self.addChildAndStart(coordinator) { [unowned self] result in
                self.peopleNavController.dismiss(animated: true) {
                    continuation.resume(returning: result)
                }
            }

            self.router.present(coordinator, source: self.peopleNavController, cancelHandler: {
                continuation.resume(returning: nil)
            })
        }
    }

    private func createConnection(with user: User) async -> Connection? {
        do {
            return try await CreateConnection(to: user).makeRequest(andUpdate: [], viewsToIgnore: [])
        } catch {
            await ToastScheduler.shared.schedule(toastType: .error(error))
            logError(error)
            return nil
        }
    }

    // MARK: - Reservations Flow

    private enum InviteNotePrompt {
        case cancelled
        case confirmed(String)
    }

    @MainActor
    private func promptForInviteNote(
        contact: CNContact,
        existingMessage: String?
    ) async -> InviteNotePrompt {
        return await withCheckedContinuation { continuation in
            let firstName = contact.givenName.isEmpty ? "them" : contact.givenName
            let alert = UIAlertController(
                title: "Invite \(firstName)",
                message: "Add an optional note (up to 140 characters).",
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.placeholder = "Want to connect on Jibber?"
                textField.text = existingMessage
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: .cancelled)
            })
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                let note = alert.textFields?.first?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: .confirmed(String(note.prefix(140))))
            })
            self.peopleNavController.present(alert, animated: true)
        }
    }

    @MainActor
    private func shareInvitation(
        with person: Person,
        contact: CNContact,
        preferredReservation: Reservation?
    ) async {
        let wasReminder = preferredReservation?.contactId == contact.identifier
        let prompt = await self.promptForInviteNote(
            contact: contact,
            existingMessage: preferredReservation?.inviteMessage
        )
        guard case .confirmed(let note) = prompt else { return }

        do {
            let requestId = self.invitationRequestIds[contact.identifier]
                ?? UUID().uuidString
            self.invitationRequestIds[contact.identifier] = requestId
            let response = try await PreparePersonInvitation(
                message: note,
                requestId: requestId,
                reservationId: preferredReservation?.objectId
            ).makeRequest(
                andUpdate: [],
                viewsToIgnore: [self.peopleNavController.view]
            )
            guard let reservationId = response["reservationId"] as? String else {
                throw ClientError.apiError(detail: "Invitation did not include a reservation")
            }

            let reservation = try await Reservation.getObject(with: reservationId)
            reservation.contactId = contact.identifier
            reservation.conversationCid = self.selectedConversationId
            _ = try await reservation.saveLocalThenServer()
            await reservation.prepareMetadata()

            self.selectedReservation = reservation
            self.sharedPerson = person
            AnalyticsManager.shared.trackEvent(
                type: .appClipShareCreated,
                properties: [
                    "allocation": response["allocation"] as? String ?? "unknown",
                    "kind": "invite"
                ]
            )

            let activityController = ActivityViewController(
                with: self,
                activityItems: reservation.activityItems(reminder: wasReminder)
            )
            await withCheckedContinuation { continuation in
                self.shareContinuation = continuation
                self.peopleNavController.present(activityController, animated: true)
            }
        } catch {
            await ToastScheduler.shared.schedule(toastType: .error(error))
        }
    }

    // MARK: - Flow Finishing

    @MainActor
    func finishInviting() async {
        await self.peopleNavController.peopleVC.finishInviting()
        
        if self.invitedPeople.count >= 3 {
            AchievementsManager.shared.createIfNeeded(with: .groupOfPlus)
        }
        
        if self.invitedPeople.count >= 1 {
            AchievementsManager.shared.createIfNeeded(with: .firstGroup)
        }
        
        self.finishFlow(with: self.invitedPeople)
    }
}

// MARK: - Rich Sharing Flow

extension PeopleCoordinator: ActivityViewControllerDelegate {

    func activityView(
        _ controller: ActivityViewController,
        didCompleteWith result: ActivityViewController.Result
    ) {
        defer {
            if let contactId = self.selectedReservation?.contactId {
                self.invitationRequestIds.removeValue(forKey: contactId)
            }
            self.shareContinuation?.resume(returning: ())
            self.shareContinuation = nil
            self.sharedPerson = nil
        }

        if result.didShare {
            var properties: [String: Any] = [:]
            if let rsvp = self.selectedReservation?.objectId {
                properties = ["value": rsvp]
            }
            AchievementsManager.shared.createIfNeeded(with: .sendInvite)
            AnalyticsManager.shared.trackEvent(type: .inviteSent, properties: properties)
            if let person = self.sharedPerson {
                self.showSentTextToast(for: person)
            }
        }
    }

    private func showSentTextToast(for person: PersonType) {
        let text = LocalizedString(id: "", arguments: [person.fullName], default: "Your RSVP has been sent to @(name). As soon as they accept, a conversation will be created between the two of you.")

        Task {
            await ToastScheduler.shared.schedule(toastType: .basic(identifier: Lorem.randomString(),
                                                                   displayable: person,
                                                                   title: "RSVP Sent",
                                                                   description: text,
                                                                   deepLink: nil))
        }
    }
}
