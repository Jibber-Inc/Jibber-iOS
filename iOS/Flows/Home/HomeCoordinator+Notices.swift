//
//  HomeCoordinator+Notices.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/9/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore

extension HomeCoordinator {
    
    // The primary action
    func handleRightOption(with notice: SystemNotice) {
        switch notice.type {
        case .connectionRequest:
            Task {
                guard let connectionId = notice.attributes?["connectionId"] as? String,
                      let connection = PeopleStore.shared.allConnections.first(where: { existing in
                          return existing.objectId == connectionId
                      }), let user = try? await connection.nonMeUser?.retrieveDataIfNeeded() else { return }
                
                do {
                    try await UpdateConnection(connectionId: connectionId, status: .accepted)
                        .makeRequest(andUpdate:[], viewsToIgnore: [])
                                    
                    let text = "Your are now connected to \(user.fullName)."
                    
                    await ToastScheduler.shared.schedule(toastType: .basic(identifier: connectionId,
                                                                     displayable: user,
                                                                     title: "Connection Accepted",
                                                                     description: text,
                                                                     deepLink: nil))
                    NoticeStore.shared.delete(notice: notice)
                    self.homeVC.noticesVC.reloadNotices()
                } catch {
                    await ToastScheduler.shared.schedule(toastType: .error(error))
                    logError(error)
                }
            }
        case .connectionConfirmed:
            guard let connectionId = notice.attributes?["connectionId"] as? String,
                  let connection = PeopleStore.shared.allConnections.first(where: { existing in
                      return existing.objectId == connectionId
                  }), let nonMeUser = connection.nonMeUser else { return }
            self.presentProfile(for: nonMeUser)
            NoticeStore.shared.delete(notice: notice)
            self.homeVC.noticesVC.reloadNotices()
        default:
            break 
        }
    }
    
    // The secondary action
    func handleLeftOption(with notice: SystemNotice) {

        switch notice.type {
        case .connectionRequest:
            Task {
                do {
                    guard let connectionId = notice.attributes?["connectionId"] as? String else { return }
                    _ = try await UpdateConnection(connectionId: connectionId, status: .declined)
                        .makeRequest(andUpdate:[], viewsToIgnore: [])
                    NoticeStore.shared.delete(notice: notice)
                    self.homeVC.noticesVC.reloadNotices()
                } catch {
                    logError(error)
                }
            }
        default:
            break
        }
    }
}
