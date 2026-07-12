//
//  HomeViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/9/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Coordinator
import Transitions

enum HomeState {
    case initial
    case tabs
    case shortcuts
    case dismissShortcuts
}

protocol HomeStateHandler {
    func handleHome(state: HomeState)
}

protocol HomeContentType {
    var contentTitle: String { get }
}

typealias HomeContentController = UIViewController & HomeContentType

class HomeViewController: ViewController, HomeStateHandler {
    
    private let topGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor,
                                                                 ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                          startPoint: .topCenter,
                                                          endPoint: .bottomCenter)
    
    private let bottomGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor, ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                             startPoint: .bottomCenter,
                                                             endPoint: .topCenter)
    
    private let titleLabel = ThemeLabel(font: .mediumBold)
    
    lazy var conversationsVC = ConversationsViewController()
    lazy var membersVC = MembersViewController()
    lazy var walletVC = WalletViewController()
    lazy var shortcutVC = ShortcutViewController()
    lazy var noticesVC = NoticesViewController() 
    
    private let shortcutButton = ShortcutButton()
    
    private var currentContentVC: HomeContentController?
    
    let tabView = TabView()
    
    @Published var state: HomeState = .initial
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.set(backgroundColor: .B0)
        self.addChild(self.shortcutVC)
        
        self.view.addSubview(self.topGradientView)
        self.view.addSubview(self.titleLabel)
        self.titleLabel.alpha = 0

        self.view.addSubview(self.bottomGradientView)
        self.view.addSubview(self.tabView)
        self.view.addSubview(self.shortcutButton)
        
        self.shortcutVC.view.didSelect { [unowned self] in
            self.state = .dismissShortcuts
        }
        
        self.shortcutButton.button.didSelect { [unowned self] in
            self.state = self.state == .shortcuts ? .dismissShortcuts : .shortcuts
        }
        
        self.tabView.$state
            .removeDuplicates()
            .mainSink { [unowned self] state in
                self.handleTab(state: state)
        }.store(in: &self.cancellables)
        
        self.$state
            .removeDuplicates()
            .mainSink { [unowned self] state in
                self.view.subviews.forEach { subview in
                    if let handler = subview as? HomeStateHandler {
                        handler.handleHome(state: state)
                    }
                }
                self.shortcutVC.handleHome(state: state)
                self.handleHome(state: state)
        }.store(in: &self.cancellables)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.state = .tabs
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.topGradientView.expandToSuperviewWidth()
        self.topGradientView.height = 100
        self.topGradientView.pin(.top)
        
        self.titleLabel.setSize(withWidth: Theme.getPaddedWidth(with: self.view.width))
        self.titleLabel.pinToSafeAreaTop()
        self.titleLabel.centerOnX()
        
        self.shortcutButton.squaredSize = ShortcutButton.height 
        self.shortcutButton.pin(.left, offset: .screenPadding)
        self.shortcutButton.pinToSafeAreaBottom()
        
        self.tabView.height = 60
        self.tabView.width = self.view.width * 0.7
        self.tabView.pinToSafeAreaBottom()
        
        switch self.state {
        case .initial:
            self.tabView.match(.left, to: .right, of: self.view)
        case .tabs:
            let offset = self.view.width * 0.05
            self.tabView.pin(.right, offset: .negative(.custom(offset)))
        case .shortcuts, .dismissShortcuts:
            self.tabView.match(.left, to: .right, of: self.view)
        }

        self.bottomGradientView.expandToSuperviewWidth()
        self.bottomGradientView.height = self.view.height - self.tabView.top
        self.bottomGradientView.pin(.bottom)
        
        if let vc = self.currentContentVC {
            vc.view.expandToSuperviewSize()
        }
        
        self.shortcutVC.view.expandToSuperviewSize()
    }
    
    private var stateTask: Task<Void, Never>?

    func handleHome(state: HomeState) {
        self.stateTask?.cancel()
        
        if state == .shortcuts {
            self.view.insertSubview(self.shortcutVC.view, belowSubview: self.shortcutButton)
            self.view.layoutNow()
        }
        
        self.stateTask = Task { [weak self] in
            guard let self else { return }
            
            await UIView.awaitSpringAnimation(with: .slow) {
                self.view.layoutNow()
            }
            
            if state == .dismissShortcuts {
                self.state = .tabs
            }
        }
    }
    
    private var loadTask: Task<Void, Never>?
    
    private func handleTab(state: TabView.State) {
        
        self.loadTask?.cancel()
        
        self.loadTask = Task { [weak self] in
            guard let self else { return }
            
            let center = self.titleLabel.center

            if let vc = self.currentContentVC {
                await UIView.awaitAnimation(with: .fast) {
                    vc.view.alpha = 0.0
                    self.titleLabel.alpha = 0
                    self.titleLabel.layer.position = center 
                    self.titleLabel.transform = CGAffineTransform.init(scaleX: 0.9, y: 0.9)
                    self.view.layoutNow()
                }
            }
            
            guard !Task.isCancelled else { return }
            
            self.children.forEach { child in
                child.removeFromParent()
            }
            
            switch state {
            case .members:
                self.currentContentVC = self.membersVC
            case .conversations:
                self.currentContentVC = self.conversationsVC
            case .wallet:
                self.currentContentVC = self.walletVC
            case .notices:
                self.currentContentVC = self.noticesVC
            }
            
            guard let vc = self.currentContentVC else { return }
            
            self.titleLabel.setText(vc.contentTitle)
            self.titleLabel.alpha = 0
            self.titleLabel.transform = CGAffineTransform.init(scaleX: 0.9, y: 0.9)
            
            vc.view.alpha = 0
            self.addChild(vc)
            self.view.insertSubview(vc.view, belowSubview: self.topGradientView)
            self.view.layoutNow()
            
            await UIView.awaitAnimation(with: .fast, animations: {
                vc.view.alpha = 1.0
                self.titleLabel.layer.position = center 
                self.titleLabel.alpha = 1
                self.titleLabel.transform = .identity
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
