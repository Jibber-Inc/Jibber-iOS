//
//  UnreadMessagesCounter.swift
//  Jibber
//
//  Created by Benji Dodgson on 4/4/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ScrollCounter
import Combine

class UnreadMessagesCounter: BaseView {
    
    let imageView = SymbolImageView(symbol: .chevronUp)
    let circle = BaseView()
    
    let countCircle = BaseView()
    
    let counter = NumberScrollCounter(value: 0,
                                      scrollDuration: Theme.animationDurationSlow,
                                      decimalPlaces: 0,
                                      prefix: "",
                                      suffix: nil,
                                      seperator: "",
                                      seperatorSpacing: 0,
                                      font: FontType.small.font,
                                      textColor: ThemeColor.white.color,
                                      animateInitialValue: true,
                                      gradientColor: nil,
                                      gradientStop: nil)
    
    private var controller: MessageSequenceController?
    private var subscriptions = Set<AnyCancellable>()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.circle)
        
        self.circle.set(backgroundColor: .B1withAlpha)
        self.circle.layer.cornerRadius = Theme.innerCornerRadius
        self.circle.layer.borderColor = ThemeColor.BORDER.color.cgColor
        self.circle.layer.borderWidth = 0.5
        
        self.clipsToBounds = false
        
        self.addSubview(self.imageView)
        self.imageView.tintColor = ThemeColor.white.color.resolvedColor(with: self.traitCollection)
        
        self.addSubview(self.countCircle)
        self.countCircle.set(backgroundColor: .D6)
        
        self.addSubview(self.counter)
        
        ConversationsManager.shared.$activeController.mainSink { [weak self] active in
            self?.configure(with: active)
        }.store(in: &self.cancellables)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.squaredSize = 44
        
        self.circle.expandToSuperviewSize()
        self.circle.makeRound()
        
        self.imageView.sizeToFit()
        self.imageView.centerOnXAndY()
        
        self.counter.sizeToFit()

        self.countCircle.width = self.counter.width + Theme.ContentOffset.long.value
        self.countCircle.height = 20
        self.countCircle.makeRound()

        self.counter.pin(.right, offset: .custom(2))
        self.counter.y = -2
        
        self.countCircle.center = self.counter.center
    }
    
    private func configure(with controller: MessageSequenceController?) {
        self.subscriptions.forEach { $0.cancel() }
        self.subscriptions.removeAll()
        self.controller = controller

        guard let controller else {
            self.update(count: 0)
            return
        }

        self.update(count: controller.messageSequence?.totalUnread ?? 0)
        self.subscribeToUpdates(for: controller)
    }

    /// The last input state the counter has received.
    private var inputState: SwipeableInputAccessoryViewController.InputState = .collapsed

    func updateVisibility(for state: SwipeableInputAccessoryViewController.InputState) {
        self.inputState = state

        switch state {
        case .collapsed:
            self.animate(shouldShow: self.counter.currentValue != 0)
        case .expanded:
            self.animate(shouldShow: false)
        }
    }
    
    private func subscribeToUpdates(for controller: MessageSequenceController) {
        controller
            .messageSequenceChangePublisher
            .mainSink { [weak self] event in
                guard let self else { return }
                switch event {
                case .update(let sequence), .create(let sequence):
                    self.update(count: sequence.totalUnread)
                case .remove:
                    self.update(count: 0)
                }
            }.store(in: &self.subscriptions)

        controller
            .messagesChangesPublisher
            .mainSink(receiveValue: { [weak self] _ in
                guard let self else { return }
                guard let sequence = self.controller?.messageSequence else {
                    return
                }

                self.update(count: sequence.totalUnread)
            }).store(in: &self.subscriptions)
    }
    
    private func update(count: Int) {
        self.counter.setValue(Float(count))

        if count == 0 {
            self.animate(shouldShow: false)
        } else if self.inputState == .collapsed {
            self.animate(shouldShow: true)
        }
    }
    
    private func animate(shouldShow: Bool, delay: TimeInterval = 0.0) {
        UIView.animate(withDuration: Theme.animationDurationFast, delay: delay) {
            self.alpha = shouldShow ? 1.0 : 0.0
            self.layoutNow()
        }
    }
}
