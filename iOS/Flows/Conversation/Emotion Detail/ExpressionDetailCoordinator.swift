//
//  EmotionDetailCoordinator.swift
//  Jibber
//
//  Created by Martin Young on 4/25/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator

class ExpressionDetailCoordinator: PresentableCoordinator<Void> {

    private let startingExpression: ExpressionInfo
    private let expressions: [ExpressionInfo]
    private let message: Messageable
    
    private lazy var emotionDetailVC: ExpressionDetailViewController = {
        return ExpressionDetailViewController(startingExpression: self.startingExpression,
                                              expressions: self.expressions,
                                              message: self.message, 
                                              delegate: self)
    }()

    override func toPresentable() -> DismissableVC {
        return self.emotionDetailVC
    }

    init(router: CoordinatorRouter,
         deepLink: DeepLinkable?,
         message: Messageable,
         startingExpression: ExpressionInfo,
         expressions: [ExpressionInfo]) {

        self.message = message
        self.startingExpression = startingExpression
        self.expressions = expressions

        super.init(router: router, deepLink: deepLink)
    }
    
    override func start() {
        super.start()
        
        self.emotionDetailVC.button.didSelect { [unowned self] in
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
            
            let controller = MessageController.controller(for: self.message)

            Task {
                do {
                    try await controller?.add(expression: expression)
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
            self.emotionDetailVC.dismiss(animated: true) {
                finishedHandler?(result)
            }
        }
        
        self.router.present(coordinator, source: self.emotionDetailVC, cancelHandler: cancelHandler)
    }
}

extension ExpressionDetailCoordinator: ExpressionDetailViewControllerDelegate {

    func emotionDetailViewControllerDidFinish(_ controller: ExpressionDetailViewController) {
        self.finishFlow(with: ())
    }
}
