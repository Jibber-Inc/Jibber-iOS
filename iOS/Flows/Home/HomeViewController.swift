//
//  HomeViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/9/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Transitions

class HomeViewController: ViewController {
        
    private let topGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor,
                                                                 ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                          startPoint: .topCenter,
                                                          endPoint: .bottomCenter)
    
    private let bottomGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor, ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                             startPoint: .bottomCenter,
                                                             endPoint: .topCenter)
    
    lazy var conversationsVC = ConversationsViewController()
    lazy var membersVC = MembersViewController()
    lazy var noticesVC = NoticesViewController()
    
    private var currentVC: UIViewController?
    
    let tabView = TabView()
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.set(backgroundColor: .B0)
        self.view.addSubview(self.topGradientView)
        self.view.addSubview(self.bottomGradientView)
        self.view.addSubview(self.tabView)
        
        self.tabView.$state
            .removeDuplicates()
            .mainSink { [unowned self] state in
                self.handle(state: state)
        }.store(in: &self.cancellables)        
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.topGradientView.expandToSuperviewWidth()
        self.topGradientView.height = 80
        self.topGradientView.pin(.top)
        
        self.tabView.height = 80
        self.tabView.width = self.view.width - Theme.ContentOffset.screenPadding.value.doubled
        self.tabView.pinToSafeAreaBottom()
        self.tabView.centerOnX()
        
        self.bottomGradientView.expandToSuperviewWidth()
        self.bottomGradientView.height = self.view.height - self.tabView.top
        self.bottomGradientView.pin(.bottom)
        
        if let vc = self.currentVC {
            vc.view.expandToSuperviewSize()
        }
    }
    
    private var loadTask: Task<Void, Never>?
    
    private func handle(state: TabView.State) {
        
        self.loadTask?.cancel()
        
        self.loadTask = Task { [weak self] in
            guard let `self` = self else { return }
            
            if let vc = self.currentVC {
                await UIView.awaitAnimation(with: .fast) {
                    vc.view.alpha = 0.0
                }
            }
            
            guard !Task.isCancelled else { return }
            
            self.children.forEach { child in
                child.removeFromParent()
            }
            
            switch state {
            case .members:
                self.currentVC = self.membersVC
            case .conversations:
                self.currentVC = self.conversationsVC
            }
            
            guard let vc = self.currentVC else { return }
            
            vc.view.alpha = 0
            self.addChild(vc)
            self.view.insertSubview(vc.view, belowSubview: self.topGradientView)
            self.view.layoutNow()
            
            await UIView.awaitAnimation(with: .fast, animations: {
                vc.view.alpha = 1.0
            })
        }
    }
}

extension HomeViewController: TransitionableViewController {

    var presentationType: TransitionType {
        return .fadeOutIn
    }

    var dismissalType: TransitionType {
        return self.presentationType
    }

    func getFromVCPresentationType(for toVCPresentationType: TransitionType) -> TransitionType {
        return toVCPresentationType
    }

    func getToVCDismissalType(for fromVCDismissalType: TransitionType) -> TransitionType {
        return fromVCDismissalType
    }
}
