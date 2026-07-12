//
//  ConversationListViewController+Extensions.swift
//  Jibber
//
//  Created by Martin Young on 11/12/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import KeyboardManager

extension ConversationViewController {

    func setupInputHandlers() {
        self.dataSource.handleCollectionViewTapped = { [unowned self] in
            if self.messageInputController.swipeInputView.textView.isFirstResponder {
                self.messageInputController.swipeInputView.textView.resignFirstResponder()
            }
        }
    }

    func subscribeToUIUpdates() {
        self.messageInputController.$inputState
            .removeDuplicates()
            .mainSink { [unowned self] state in
                UIView.animate(withDuration: Theme.animationDurationFast) {
                    self.headerVC.view.alpha = state == .collapsed ? 1.0 : 0.5
                }
            }.store(in: &self.cancellables)
        
        self.$state
            .removeDuplicates()
            .mainSink { [unowned self] state in
                self.updateUI(for: state)
            }.store(in: &self.cancellables)
        
        KeyboardManager.shared
            .$currentEvent
            .mainSink { [weak self] currentEvent in
                guard let self else { return }

                switch currentEvent {
                case .willShow:
                    self.state = .write
                case .willHide:
                    self.state = .read
                case .didChangeFrame:
                    self.view.setNeedsLayout()
                default:
                    break
                }
            }.store(in: &self.cancellables)
    }
    
    func subscribeToConversationUpdates() {
        guard let controller = self.conversationController else { return }
        self.conversationUpdateCancellable = controller
            .conversationChangePublisher
            .mainSink { [unowned self] _ in
                Task {
                    await self.dataSource.update(with: controller)
                }.add(to: self.autocancelTaskPool)
            }

        self.typingInputCancellable = self.messageInputController.swipeInputView.textView.$inputText
            .map { !$0.isEmpty }
            .removeDuplicates()
            .mainSink { [weak self] isTyping in
                self?.updateTypingState(isTyping)
            }
    }

    private func updateTypingState(_ isTyping: Bool) {
        self.typingHeartbeatTask?.cancel()
        guard let conversationController = self.getCurrentConversationController(),
              conversationController.areTypingEventsEnabled else { return }

        try? conversationController.setTyping(isTyping)
        guard isTyping else { return }

        self.typingHeartbeatTask = Task { @MainActor [weak self, weak conversationController] in
            while !Task.isCancelled {
                await Task.sleep(seconds: 8)
                guard !Task.isCancelled,
                      let self,
                      let conversationController,
                      self.getCurrentConversationController() === conversationController else { return }
                try? conversationController.setTyping(true)
            }
        }
    }
}
