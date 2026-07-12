//
//  ShortcutViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/14/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator

class ShortcutViewController: ViewController, HomeStateHandler {
    
    private let blurView = DarkBlurView()
    
    let option1 = ShortcutOptionView(with: .newMoment)
    let option2 = ShortcutOptionView(with: .updateVibe)
    let option3 = ShortcutOptionView(with: .newMessage)
    
    var didSelectOption: ((ShortcutOptionView.OptionType) -> Void)? = nil
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.addSubview(self.blurView)
        self.blurView.showBlur(false)
        
        self.view.addSubview(self.option1)
        self.option1.didSelectOption = { [unowned self] option in
            self.didSelectOption?(option)
        }
        self.view.addSubview(self.option2)
        self.option2.didSelectOption = { [unowned self] option in
            self.didSelectOption?(option)
        }
        self.view.addSubview(self.option3)
        self.option3.didSelectOption = { [unowned self] option in
            self.didSelectOption?(option)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.option1.pinToSafeAreaBottom()
        self.option1.pin(.left, offset: .screenPadding)
        
        self.option2.match(.bottom, to: .bottom, of: self.option1)
        self.option2.pin(.left, offset: .screenPadding)
        
        self.option3.match(.bottom, to: .bottom, of: self.self.option2)
        self.option3.pin(.left, offset: .screenPadding)
        
        self.blurView.expandToSuperviewSize()
    }
    
    private var stateTask: Task<Void, Never>?

    func handleHome(state: HomeState) {
        self.stateTask?.cancel()
        
        self.stateTask = Task { [weak self] in
            guard let self else { return }
            
            switch state {
            case .initial, .tabs, .dismissShortcuts:
                if self.blurView.effect.isNil {
                    await self.animateBlur(for: state)
                    await self.animateOptions(for: state)
                } else {
                    await self.animateOptions(for: state)
                    await self.animateBlur(for: state)
                }
                self.view.removeFromSuperview()

            case .shortcuts:
                await self.animateBlur(for: state)
                await self.animateOptions(for: state)
            }
        }
    }
    
    private func animateOptions(for state: HomeState) async {
        let startingBottonOffset: CGFloat = self.view.height - (self.view.safeAreaInsets.bottom + Theme.ContentOffset.long.value.doubled.doubled + ShortcutButton.height)
        
        async let first: () = UIView.awaitAnimation(with: .fast, delay: 0.0, options: .curveEaseIn) {
            switch state {
            case .initial, .tabs, .dismissShortcuts:
                self.option3.alpha = 0
                self.option3.bottom = startingBottonOffset - self.option3.height - Theme.ContentOffset.long.value
            case .shortcuts:
                self.option1.alpha = 1.0
                self.option1.bottom = startingBottonOffset
            }
        }
        
        async let second: () = UIView.awaitAnimation(with: .fast, delay: 0.1, options: .curveEaseIn) {
            switch state {
            case .initial, .tabs, .dismissShortcuts:
                self.option2.alpha = 0
                self.option2.bottom = startingBottonOffset
            case .shortcuts:
                self.option2.alpha = 1
                self.option2.bottom = startingBottonOffset - self.option2.height - Theme.ContentOffset.long.value
            }
        }
        
        async let third: () = UIView.awaitAnimation(with: .fast, delay: 0.2, options: .curveEaseIn) {
            switch state {
            case .initial, .tabs, .dismissShortcuts:
                self.option1.alpha = 0
                self.option1.pinToSafeAreaBottom()
            case .shortcuts:
                self.option3.alpha = 1
                self.option3.bottom = startingBottonOffset - self.option3.height.doubled - Theme.ContentOffset.long.value.doubled
            }
        }
        
        await _ = [first, second, third]
    }
    
    private func animateBlur(for state: HomeState) async {
        await UIView.awaitAnimation(with: .fast, animations: {
            switch state {
            case .initial, .tabs, .dismissShortcuts:
                self.blurView.showBlur(false)
            case .shortcuts:
                self.blurView.showBlur(true)
            }
        })
    }
}
