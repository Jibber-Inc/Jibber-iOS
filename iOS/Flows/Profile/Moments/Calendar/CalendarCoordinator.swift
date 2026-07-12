//
//  CalendarCoordinator.swift
//  Jibber
//
//  Created by Benji Dodgson on 9/5/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Coordinator

class CalendarCoordinator: PresentableCoordinator<ProfileResult?> {
    
    lazy var calendarVC = CalendarViewController(with: self.person)
    private let person: PersonType
    
    init(with person: PersonType,
         router: CoordinatorRouter,
         deepLink: DeepLinkable?) {
        
        self.person = person
        super.init(router: router, deepLink: deepLink)
    }

    override func toPresentable() -> DismissableVC {
        return self.calendarVC
    }
    
    override func start() {
        super.start()
        
        self.calendarVC.dataSource.momentDelegate = self 
        
        self.calendarVC.$selectedItems.mainSink { [unowned self] items in
            guard let first = items.first else { return }
            
            switch first {
            case .moment(let model):
                guard model.isAvailable else { return }
                Task {
                    if let moment = try? await Moment.getObject(with: model.momentId) {
                        self.presentMoment(with: moment)
                    } else {
                        await ToastScheduler.shared.schedule(toastType: .success(.eyeSlash,
                                                                                 "No Moment Recorded"),
                                                             position: .bottom,
                                                             duration: 3)
                    }
                }
            }
            
        }.store(in: &self.cancellables)
    }
    
    func presentMoment(with moment: Moment) {
        self.removeChild()
        
        let coordinator = MomentCoordinator(moment: moment, router: self.router, deepLink: self.deepLink)
        self.addChildAndStart(coordinator) { [unowned self] result in
            if let result = result {
                self.finishFlow(with: result)
            } else {
                self.calendarVC.dismiss(animated: true)
            }
        }
        self.router.present(coordinator, source: self.calendarVC, cancelHandler: nil)
    }
    
    func presentMomentCapture() {
        
        self.removeChild()
        let coordinator = MomentCaptureCoordinator(router: self.router, deepLink: self.deepLink)
        
        self.addChildAndStart(coordinator) { _ in }
        
        self.router.present(coordinator, source: self.calendarVC, cancelHandler: nil)
    }
}

extension CalendarCoordinator: MomentCellDelegate {
    func moment(_ cell: MomentCell, didSelect moment: Moment) {
        self.presentMoment(with: moment)
    }
    
    func momentCellDidSelectRecord(_ cell: MomentCell) {
        self.presentMomentCapture()
    }
}
