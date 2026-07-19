//
//  PersonConnectionCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 5/16/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import ParseCore
import UIKit

class PersonConnectionCoordinator: PresentableCoordinator<Connection?> {
    
    lazy var vc = PersonConnectionViewController()
    private let person: PersonType?
    private let launchActivity: LaunchActivity? 
    
    init(with person: PersonType? = nil ,
         launchActivity: LaunchActivity? = nil,
         router: CoordinatorRouter,
         deepLink: DeepLinkable?) {
        
        self.person = person
        self.launchActivity = launchActivity
        
        super.init(router: router, deepLink: deepLink)
    }

    override func toPresentable() -> DismissableVC {
        return self.vc
    }
    
    override func start() {
        super.start()
        
        self.vc.button.didSelect { [unowned self] in
            Task {
                do {
                    let connection = try await self.handleDidTapConnect()
                    self.finishFlow(with: connection)
                } catch {
                    await self.vc.button.handleEvent(status: .error(error.localizedDescription))
                    await ToastScheduler.shared.schedule(toastType: .error(error))
                }
            }
        }
        
        if let person = self.person {
            self.vc.configure(for: person)
        } else if let launchActivity = launchActivity {
            switch launchActivity {
            case .onboarding(_):
                break
            case .reservation(let reservationId):
                Task { @MainActor in
                    if let context = try? await GetAppClipShareContext(
                        kind: .invite,
                        id: reservationId
                    ).makeRequest(andUpdate: [], viewsToIgnore: [self.vc.view]),
                       let inviter = context["inviter"] as? [String: Any],
                       let firstName = inviter["firstName"] as? String {
                        var image: UIImage?
                        if let avatarURL = inviter["avatarURL"] as? String,
                           let url = URL(string: avatarURL),
                           let (data, _) = try? await URLSession.shared.data(from: url) {
                            image = UIImage(data: data)
                        }
                        let avatar = SystemAvatar(
                            givenName: firstName,
                            familyName: "",
                            handle: "",
                            phoneNumber: nil,
                            image: image
                        )
                        self.vc.configure(
                            for: avatar,
                            inviteMessage: context["inviteMessage"] as? String
                        )
                    } else if let reservation = try? await Reservation
                        .getObject(with: reservationId)
                        .retrieveDataIfNeeded(),
                              let owner = try? await reservation.createdBy?
                        .retrieveDataIfNeeded() {
                        self.vc.configure(for: owner, inviteMessage: reservation.inviteMessage)
                    }
                }
            case .pass(let passId):
                Task {
                    guard let pass = try? await Pass.getObject(with: passId).retrieveDataIfNeeded(),
                            let owner = try? await pass.owner?.retrieveDataIfNeeded() else { return }
                    
                    self.vc.configure(for: owner)
                }
            case .deepLink(_):
                self.finishFlow(with: nil)
            }
        } else {
            self.finishFlow(with: nil)
        }
    }
    
    private func handleDidTapConnect() async throws -> Connection? {
        await self.vc.button.handleEvent(status: .loading)
        var toUser: User?
        if let user = self.person as? User {
            toUser = user
        } else if let launchActivity = launchActivity {
            switch launchActivity {
            case .onboarding(_):
                break
            case .reservation(let reservationId):
                let result = try await RespondToReservationInvitation(
                    reservationId: reservationId,
                    decision: .accepted
                ).makeRequest(andUpdate: [], viewsToIgnore: [self.vc.view])
                if let response = result as? [String: Any],
                   let connectionId = response["connectionId"] as? String {
                    let connection = try? await Connection.getObject(with: connectionId)
                    await self.vc.button.handleEvent(status: .complete)
                    return connection
                }
                guard let reservation = try? await Reservation
                    .getObject(with: reservationId)
                    .retrieveDataIfNeeded(),
                      let owner = try? await reservation.createdBy?.retrieveDataIfNeeded() else {
                    return nil
                }
                toUser = owner
            case .pass(let passId):
                guard let pass = try? await Pass.getObject(with: passId).retrieveDataIfNeeded(),
                        let owner = try? await pass.owner?.retrieveDataIfNeeded() else { return nil }
                toUser = owner
            case .deepLink(_):
                break
            }
        }
        
        guard let toUser = toUser else { return nil }
        
        var connection: Connection?
        if let existing = PeopleStore.shared.allConnections.first(where: { connection in
            return connection.nonMeUser?.personId == toUser.personId
        }) {
            connection = existing
            try await UpdateConnection(connectionId: existing.objectId!, status: .accepted).makeRequest(andUpdate: [], viewsToIgnore: [])
        } else {
            connection = try? await CreateConnection(to: toUser).makeRequest(andUpdate: [], viewsToIgnore: [])
        }
    
        await self.vc.button.handleEvent(status: .complete)
        
        return connection
    }
}
