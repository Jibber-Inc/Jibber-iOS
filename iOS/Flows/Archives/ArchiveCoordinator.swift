//
//  ArchiveCoordinator.swift
//  ArchiveCoordinator
//
//  Created by Benji Dodgson on 9/16/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat

#warning("Remove after beta features are complete.")
extension ArchiveCoordinator: ToastSchedulerDelegate {

    nonisolated func didInteractWith(type: ToastType, deeplink: DeepLinkable?) {
        Task.onMainActor {
            guard let link = deeplink else { return }
            self.handle(deeplink: link)
        }
    }
}

class ArchiveCoordinator: PresentableCoordinator<Void> {

    private lazy var archiveVC: ArchiveViewController = {
        let vc = ArchiveViewController()
        vc.delegate = self
        return vc
    }()

    override func toPresentable() -> DismissableVC {
        return self.archiveVC
    }

    override func start() {
        super.start()

        if let deeplink = self.deepLink {
            self.handle(deeplink: deeplink)
        }

        ToastScheduler.shared.delegate = self
    }

    func handle(deeplink: DeepLinkable) {
        self.deepLink = deeplink

        guard let target = deeplink.deepLinkTarget else { return }

        switch target {
        case .conversation:
            #warning("Replace")
//            if let conversationId = deeplink.customMetadata["conversationId"] as? String,
//               let conversation = ConversationSupplier.shared.getConversation(withSID: conversationId) {
//                self.startConversationFlow(for: conversation.conversationType)
//            } else if let connectionId = deeplink.customMetadata["connectionId"] as? String {
//                Task {
//                    do {
//                        let connection = try await Connection.getObject(with: connectionId)
//                        guard let conversationId = connection.conversationId,
//                              let conversation = ConversationSupplier.shared.getConversation(withSID: conversationId) else {
//                                  return
//                              }
//
//                        self.startConversationFlow(for: conversation.conversationType)
//                    } catch {
//                        logDebug(error)
//                    }
//                }
//            }
        default:
            break
        }
    }
}

extension ArchiveCoordinator: ArchiveViewControllerDelegate {

    nonisolated func archiveView(_ controller: ArchiveViewController, didSelect item: ArchiveCollectionViewDataSource.ItemType) {

        switch item {
        case .conversation(let conversationID):
            Task.onMainActor {
                if let conversation = ChatClient.shared.channelController(for: conversationID).conversation {
                    self.startConversationFlow(for: conversation)
                }
            }
        }
    }

    func startConversationFlow(for conversation: Conversation?) {
        self.removeChild()

        let coordinator = ConversationCoordinator(router: self.router,
                                                  deepLink: self.deepLink,
                                                  conversation: conversation)
        self.addChildAndStart(coordinator, finishedHandler: { (_) in
            self.router.dismiss(source: coordinator.toPresentable(), animated: true) {
                self.finishFlow(with: ())
            }
        })
        self.router.present(coordinator, source: self.archiveVC, animated: true)
    }
}
