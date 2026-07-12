//
//  ReactionsDetailCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/27/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator

class ReactionsDetailCoordinator: PresentableCoordinator<Void> {

    private let moment: Moment
    
    private lazy var detailVC: ReactionsDetailViewController = {
        return ReactionsDetailViewController(with: self.moment, delegate: self)
    }()

    init(router: CoordinatorRouter,
         deepLink: DeepLinkable?,
         moment: Moment) {

        self.moment = moment

        super.init(router: router, deepLink: deepLink)
    }
    
    override func toPresentable() -> DismissableVC {
        return self.detailVC
    }
    
    override func start() {
        super.start()
        
        self.detailVC.button.didSelect { [unowned self] in
            self.presentAddExpression()
        }
    }
    
    func presentAddExpression() {
        let coordinator = ExpressionCoordinator(router: self.router,
                                                deepLink: self.deepLink)
        
        self.present(coordinator) { [unowned self] result in
            guard let expression = result else { return }
            
            expression.emotions.forEach { emotion in
                AnalyticsManager.shared.trackEvent(type: .emotionSelected,
                                                   properties: ["value": emotion.rawValue])
            }
            
            let controller = ParseConversationController(
                conversationID: self.moment.commentsId,
                automaticallySynchronize: false
            )
            
            Task {
                do {
                    try await controller.add(expression: expression)
                } catch {
                    logError(error)
                }
            }
        }
    }
    
    func present<ChildResult>(_ coordinator: PresentableCoordinator<ChildResult>,
                              finishedHandler: ((ChildResult) -> Void)? = nil,
                              cancelHandler: (() -> Void)? = nil) {
        self.removeChild()

        coordinator.toPresentable().dismissHandlers.append { }
        
        self.addChildAndStart(coordinator) { [unowned self] result in
            self.detailVC.dismiss(animated: true) {
                finishedHandler?(result)
            }
        }
        
        self.router.present(coordinator, source: self.detailVC, cancelHandler: cancelHandler)
    }
}

extension ReactionsDetailCoordinator: ExpressionDetailViewControllerDelegate {

    func emotionDetailViewControllerDidFinish(_ controller: ExpressionDetailViewController) {
        self.finishFlow(with: ())
    }
}
