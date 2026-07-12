//
//  MomentContentView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/30/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Combine
import Foundation
import UIKit
import AVFoundation
import ParseCore

protocol MomentContentViewDelegate: AnyObject {
    func momentContentViewDidSelectCapture(_ view: MomentContentView)
    func momentContent(_ view: MomentContentView, didSetCaption caption: String?)
    func momentContent(_ view: MomentContentView, didSelectPerson person: PersonType)
}

extension MomentContentViewDelegate {
    func momentContent(_ view: MomentContentView, didSetCaption caption: String?) {}
}

class MomentContentView: BaseView {
    
    let menuButton = ThemeButton()
    private let detailContentView = MomentDetailContentView()
    private let expressionView = MomentExpressiontVideoView()
    private let momentView = MomentVideoView()
    let blurView = MomentBlurView()
    let captionTextView = CaptionTextView()
    private let moment: Moment
    
    var isReadyForDisplay: Bool {
        return self.momentView.playerLayer.isReadyForDisplay
    }
    
    var momentVideoItem: AVPlayerItem? {
        return self.momentView.playerLayer.player?.currentItem
    }
    
    var isPlaying: Bool {
        return self.momentView.isPlaying
    }
    
    var isShowingDetail: Bool {
        return self.detailContentView.alpha == 1.0 
    }
    
    weak var delegate: MomentContentViewDelegate?
    
    init(with moment: Moment) {
        self.moment = moment
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.translatesAutoresizingMaskIntoConstraints = false
        
        self.addSubview(self.momentView)
        self.addSubview(self.expressionView)
        self.addSubview(self.detailContentView)
        self.addSubview(self.menuButton)
        self.menuButton.set(style: .image(symbol: .ellipsis, palletteColors: [.whiteWithAlpha], pointSize: 22, backgroundColor: .clear))
        self.menuButton.showsMenuAsPrimaryAction = true
        
        self.detailContentView.alpha = 0 
        self.addSubview(self.captionTextView)
        self.addSubview(self.blurView)
        
        self.captionTextView.isEditable = false
        self.captionTextView.isSelectable = false
        
        self.blurView.button.didSelect { [unowned self] in
            self.delegate?.momentContentViewDidSelectCapture(self)
        }
        
        self.clipsToBounds = true
        
        self.blurView.configure(for: moment)
        self.detailContentView.configure(for: moment)
        self.expressionView.expression = moment.expression
        
        self.captionTextView.publisher(for: \.text).mainSink { [unowned self] text in
            self.delegate?.momentContent(self, didSetCaption: text)
        }.store(in: &self.cancellables)
        
        Task {
            guard let moment = try? await moment.retrieveDataIfNeeded() else { return }
            if let person = try? await moment.author?.retrieveDataIfNeeded() {
                self.menuButton.menu = self.createMenu(for: person)
            }
            if moment.isAvailable {
                self.captionTextView.setText(moment.caption)
                self.captionTextView.animateCaption(text: moment.caption)
                self.layoutNow()
            }
        }
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification).mainSink { [weak self] _ in
            guard let self else { return }
            self.showMomentIfAvailable()
        }.store(in: &self.cancellables)
        
        self.momentView.playerLayer.publisher(for: \.isReadyForDisplay).mainSink { [unowned self] isReady in
            if self.moment.isAvailable {
                self.blurView.animateBlur(shouldShow: !isReady)
            } else {
                self.blurView.animateBlur(shouldShow: true)
            }
        }.store(in: &self.cancellables)

        self.showMomentIfAvailable()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.blurView.expandToSuperviewSize()
        self.momentView.expandToSuperviewSize()
        
        self.expressionView.squaredSize = self.width * 0.25
        self.expressionView.pinToSafeAreaTop()
        self.expressionView.pinToSafeAreaLeft()
        
        let maxWidth = Theme.getPaddedWidth(with: self.width)
        self.captionTextView.setSize(withMaxWidth: maxWidth)
        self.captionTextView.pinToSafeAreaLeft()
        self.captionTextView.bottom = self.height - self.captionTextView.left
        self.captionTextView.isVisible = !self.captionTextView.placeholderText.isEmpty
        
        self.detailContentView.expandToSuperviewSize()
        self.detailContentView.pin(.top)
        
        self.menuButton.squaredSize = 44
        self.menuButton.pin(.top)
        self.menuButton.pinToSafeAreaRight()
    }
    
    func shouldShowOnlyMoment(_ show: Bool) {
        self.expressionView.alpha = show ? 0.0 : 1.0
        self.menuButton.alpha = show ? 0.0 : 1.0
        if self.captionTextView.text.isNotEmpty {
            self.captionTextView.alpha = show ? 0.0 : 1.0
        } else {
            self.captionTextView.alpha = 0
        }
    }
    
    func shouldShowDetail(_ show: Bool) {
        self.expressionView.alpha = show ? 0.0 : 1.0
        self.menuButton.alpha = show ? 0.0 : 1.0
        if self.captionTextView.text.isNotEmpty {
            self.captionTextView.alpha = show ? 0.0 : 1.0
        } else {
            self.captionTextView.alpha = 0
        }
        self.momentView.alpha = show ? 0.5 : 1.0
        self.detailContentView.alpha = show ? 1.0 : 0.0 
    }
    
    func showMomentIfAvailable() {
        
        self.momentView.loadPreview(for: moment)
        
        if self.moment.isAvailable {
            self.momentView.loadFullMoment(for: moment)
        }
    }
    
    func play() {
        if self.momentView.playerLayer.isReadyForDisplay {
            self.expressionView.playerLayer.player?.play()
            self.momentView.playerLayer.player?.play()
        } else {
            self.play()
        }
    }
    
    func pause() {
        self.expressionView.playerLayer.player?.pause()
        self.momentView.playerLayer.player?.pause()
    }
    
    func mute() {
        self.expressionView.playerLayer.player?.isMuted = true
        self.momentView.playerLayer.player?.isMuted = true
    }
    
    func unMute() {
        self.expressionView.playerLayer.player?.isMuted = false
        self.momentView.playerLayer.player?.isMuted = false
    }
    
    func seek(to: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        self.momentView.playerLayer.player?.seek(to: to, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
    }
    
    private func createMenu(for person: PersonType) -> UIMenu? {
        
        let profile = UIAction(title: "View Profile",
                               image: ImageSymbol.personCircle.image,
                               attributes: []) { [unowned self] action in
            self.delegate?.momentContent(self, didSelectPerson: person)
        }

        return UIMenu.init(title: "Menu",
                           image: nil,
                           identifier: nil,
                           options: [],
                           children: [profile])
    }
}

private class MomentDetailContentView: BaseView {
    
    private let nameLabel = ThemeLabel(font: .smallBold)
    private let dateLabel = ThemeLabel(font: .xtraSmall)
    #if IOS
    private let viewedLabel = ViewedLabel()
    #endif
    
    private let locationView = LocationDetailView()
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.nameLabel)
        self.addSubview(self.dateLabel)
        #if IOS
        self.addSubview(self.viewedLabel)
        #endif
        
        self.addSubview(self.locationView)
        self.locationView.isVisible = false
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.nameLabel.setSize(withWidth: self.width)
        self.nameLabel.pinToSafeAreaLeft()
        self.nameLabel.pin(.top, offset: .xtraLong)
        
        self.dateLabel.setSize(withWidth: self.width)
        self.dateLabel.pinToSafeAreaLeft()
        self.dateLabel.match(.top, to: .bottom, of: self.nameLabel, offset: .short)
        
        #if IOS
        self.viewedLabel.pinToSafeAreaRight()
        self.viewedLabel.centerY = self.nameLabel.centerY
        #endif
        
        self.locationView.height = 22
        self.locationView.width = self.halfWidth
        self.locationView.pinToSafeAreaLeft()
        self.locationView.pin(.bottom, offset: .xtraLong)
    }
    
    func configure(for moment: Moment) {
        #if IOS
        self.viewedLabel.configure(with: moment)
        #endif
        
        self.dateLabel.setText(moment.createdAt?.getTimeAgo().string ?? "")
        self.layoutNow()
        
        Task {
            guard let moment = try? await moment.retrieveDataIfNeeded() else { return }
            if let person = try? await moment.author?.retrieveDataIfNeeded() {
                self.nameLabel.setText(person.fullName.capitalized)
            }
            
            await self.locationView.configure(with: moment)
            
            self.layoutNow()
        }
    }
}
