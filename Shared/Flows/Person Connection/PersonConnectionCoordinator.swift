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
                try? await self.handleDidTapConnect()
            }
        }
        
        if let person = self.person {
            self.vc.configure(for: person)
        } else if let launchActivity = launchActivity {
            switch launchActivity {
            case .onboarding(_):
                break
            case .reservation(let reservationId):
                Task {
                    guard let reservation = try? await Reservation.getObject(with: reservationId).retrieveDataIfNeeded(), let owner = try? await reservation.createdBy?.retrieveDataIfNeeded() else { return }
                    
                    self.vc.configure(for: owner)
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
                guard let reservation = try? await Reservation.getObject(with: reservationId).retrieveDataIfNeeded(), let owner = try? await reservation.createdBy?.retrieveDataIfNeeded() else { return nil }
                
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
