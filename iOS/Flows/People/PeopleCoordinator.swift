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
import MessageUI
import Localization
import ParseCore

class PeopleCoordinator: PresentableCoordinator<[Person]> {

    private lazy var peopleNavController = PeopleNavigationController(showConnections: self.selectedConversationId.exists)
    private var messageController: MessageComposerViewController?
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
        } else if let contact = person.cnContact, let reservation = self.getReservation(for: contact) {
            
            // Get a valid reservation object that we can use to invite this person. Then prompt the user
            // to send them a text
            await self.sendText(to: contact, with: reservation)
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

    func sendText(to contact: CNContact, with reservation: Reservation) async {
        // Get the contact's phone number
        guard let phone = contact.findBestPhoneNumberString() else { return }

        // This user doesn't exist yet so they'll need the reservation to store the cid
        // in order to access the conversation.
        reservation.conversationCid = self.selectedConversationId
        
        // Used to track invites
        self.selectedReservation = reservation
        
        // If this reservation was already used to invite the contact, then just send an invite reminder text.
        if reservation.contactId == contact.identifier {
            _ = try? await reservation.saveLocalThenServer()
            await reservation.prepareMetadata()
            await self.sendText(with: reservation.reminderMessage, phone: phone)
        } else {
            // If this contact hasn't been assigned to reservation yet, then update the contact id
            // and save it to the server.
            reservation.contactId = contact.identifier
            _ = try? await reservation.saveLocalThenServer()
            await reservation.prepareMetadata()
            await self.sendText(with: reservation.message, phone: phone)
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

// MARK: - Messaging Flow

extension PeopleCoordinator: MFMessageComposeViewControllerDelegate {

    private func sendText(with message: String?, phone: String) async {
        guard MFMessageComposeViewController.canSendText() else { return }

        return await withCheckedContinuation { continuation in
            let messageComposer = MessageComposerViewController()
            messageComposer.recipients = [phone]
            messageComposer.body = message
            messageComposer.messageComposeDelegate = self

            // HACK: For some reason we need to keep a reference to the message composer to prevent
            // weird warnings from appearing when its dismissed.
            self.messageController = messageComposer

            self.peopleNavController.present(messageComposer, animated: true)

            messageComposer.dismissHandlers.append {
                continuation.resume(returning: ())
            }
        }
    }
    
    func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                      didFinishWith result: MessageComposeResult) {
        switch result {
        case .cancelled, .failed:
            controller.dismiss(animated: true)
        case .sent:
            var properties: [String: Any] = [:]
            if let rsvp = self.selectedReservation?.objectId {
                properties = ["value": rsvp]
            }
            AchievementsManager.shared.createIfNeeded(with: .sendInvite)
            AnalyticsManager.shared.trackEvent(type: .inviteSent, properties: properties)
            controller.dismiss(animated: true) {
                // Get the person object for the person that was just invited with a text.
                guard let phone = controller.recipients?.first else { return }
                guard let invitedPerson = self.peopleToInvite.first(where: { person in
                    if let contact = person.cnContact,
                       let phoneString = contact.findBestPhoneNumberString(),
                       phone == phoneString {
                        return true
                    } else {
                        return false
                    }
                }) else { return }

                guard let contact = invitedPerson.cnContact else { return }

                // The text was sent successfully so let the user know with a toast.
                let person = Person(withContact: contact)
                self.showSentTextToast(for: person)
            }
        @unknown default:
            break
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
