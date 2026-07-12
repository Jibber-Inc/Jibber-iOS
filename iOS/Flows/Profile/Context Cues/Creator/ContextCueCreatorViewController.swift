//
//  ContextCueCreatorViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/6/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Localization
import KeyboardManager
import ParseCore

class ContextCueCreatorViewController: EmojiPickerViewController {
            
    let button = ThemeButton()
    private var showButton: Bool = true
    
    var didCreateContextCue: CompletionOptional = nil
    
    override func initializeViews() {
        super.initializeViews()

        self.view.addSubview(self.button)
        self.button.didSelect { [unowned self] in
            Task {
                do {
                    try await self.createContextCue()
                    self.didCreateContextCue?()
                } catch {
                    logError(error)
                }
            }
        }
        
        self.collectionView.allowsMultipleSelection = true
        
        self.$selectedEmojis.mainSink { [unowned self] items in
            self.updateButton()
        }.store(in: &self.cancellables)
        
        KeyboardManager.shared.$cachedKeyboardEndFrame.mainSink { [unowned self] _ in
            self.view.setNeedsLayout()
        }.store(in: &self.cancellables)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.button.setSize(with: self.view.width)
        self.button.centerOnX()
        
        if self.showButton {
            if KeyboardManager.shared.isKeyboardShowing {
                self.button.bottom = self.view.height - KeyboardManager.shared.cachedKeyboardEndFrame.height - Theme.ContentOffset.long.value
            } else {
                self.button.pinToSafeAreaBottom()
            }
        } else {
            self.button.top = self.view.height
        }
    }
    
    private func updateButton() {
        self.button.set(style: .custom(color: .white, textColor: .B0, text: self.getButtonTitle()))
        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.showButton = self.selectedEmojis.count > 0
            self.view.layoutNow()
        }
    }
    
    private func getButtonTitle() -> Localized {

        var emojiText = ""
        let max: Int = 3
        for (index, value) in self.selectedEmojis.enumerated() {
            if index <= max - 1 {
                emojiText.append(contentsOf: value.emoji)
            }
        }
        
        if self.selectedEmojis.count > max {
            let amount = self.selectedEmojis.count - max
            emojiText.append(contentsOf: " +\(amount)")
        }
        
        return "Add: \(emojiText)"
    }
    
    private func createContextCue() async throws {
        
        await self.button.handleEvent(status: .loading)
        
        let emojis: [String] = self.selectedEmojis.compactMap { type in
            return type.emoji
        }
        
        let contextCue = ContextCue()
        contextCue.emojis = emojis
        contextCue.owner = User.current()
        
        guard let saved = try? await contextCue.saveToServer() else {
            await self.button.handleEvent(status: .complete)
            return
        }
        
        User.current()?.latestContextCue = saved
        try await User.current()?.saveToServer()
        
        await self.button.handleEvent(status: .complete)
        
        await ToastScheduler.shared.schedule(toastType: .newContextCue(saved))
        
        AnalyticsManager.shared.trackEvent(type: .contextCueCreated, properties: ["value": saved.emojiString])
    }
}
