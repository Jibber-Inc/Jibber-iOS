//
//  MomentDetailViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/3/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import AVKit
import Coordinator
import ParseCore

class MomentViewController: ViewController {
    
    private let moment: Moment
    
    let footerView = MomentFooterView()
    lazy var contentView = MomentContentView(with: self.moment)
    
    // time when scrubbing began
    private var scrubbingBeginTime: CMTime?
    
    init(with moment: Moment) {
        self.moment = moment
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.modalPresentationStyle = .popover
        if let pop = self.popoverPresentationController {
            let sheet = pop.adaptiveSheetPresentationController
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.preferredCornerRadius = Theme.screenRadius
        }
        
        self.view.set(backgroundColor: .B0)
        
        self.view.addSubview(self.contentView)
        self.contentView.layer.cornerRadius = Theme.screenRadius
        self.contentView.layer.masksToBounds = true
        
        self.view.addSubview(self.footerView)
        
        let panGesture = UIPanGestureRecognizer()
        panGesture.delegate = self
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2
        panGesture.cancelsTouchesInView = true
        panGesture.addTarget(self, action: #selector(didScrub(recognizer:)))
        self.contentView.addGestureRecognizer(panGesture)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handle))
        longPress.delegate = self
        longPress.minimumPressDuration = 0.25

        self.contentView.addGestureRecognizer(longPress)
        
        self.contentView.didSelect { [unowned self] in
            if self.contentView.isShowingDetail {
                UIView.animate(withDuration: Theme.animationDurationFast) {
                    self.contentView.shouldShowDetail(false)
                    self.footerView.alpha = 1.0
                }
                
                self.contentView.unMute()
            } else {
                UIView.animate(withDuration: Theme.animationDurationFast) {
                    self.contentView.shouldShowDetail(true)
                    self.footerView.alpha = 0.0
                }
                
                self.contentView.mute()
            }
        }
        
        self.showMomentIfAvailable()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.contentView.expandToSuperviewWidth()
        self.contentView.height = self.view.height - self.view.safeAreaInsets.bottom - self.view.height * 0.15
        self.contentView.pin(.top)
        
        self.footerView.expandToSuperviewWidth()
        self.footerView.height = self.view.height - self.contentView.height
        self.footerView.match(.top, to: .bottom, of: self.contentView)
    }
    
    func showMomentIfAvailable() {
        self.contentView.showMomentIfAvailable()
        
        if self.moment.isAvailable {
            #if IOS
            // If the user has not been added to the comments convo, add them. This will represent views.
            let controller = ConversationController.controller(for: self.moment.commentsId)
            controller.addMembers(userIds: Set([User.current()!.objectId!])) { [unowned self] error in
                self.footerView.configure(for: self.moment)
            }
            #elseif APPCLIP
            self.footerView.configure(for: self.moment)
            #endif
        } else {
            self.footerView.configure(for: self.moment)
        }
    }
    
    @objc private func didScrub(recognizer: UIPanGestureRecognizer) {
        
        guard self.contentView.isReadyForDisplay == true,
              let currentItem = self.contentView.momentVideoItem else {
            return
        }
        
        switch recognizer.state {
        case .possible:
            // nothing to do here
            break
        case .began:
            // pause playback when user begins panning
            self.contentView.pause()
            
            // set time scrubbing began
            self.scrubbingBeginTime = currentItem.currentTime()
        case .changed:
            guard let scrubbingBeginTime = self.scrubbingBeginTime else {
                return
            }
            let totalSeconds = currentItem.duration.seconds
            // translate point of pan in view
            let point = recognizer.translation(in: self.view)
            let scrubbingBeginPercent = Double(scrubbingBeginTime.seconds/totalSeconds)
            // calculate percentage of point in view
            var percent = Double(point.x/self.view.bounds.width)
            percent += scrubbingBeginPercent
            if percent < 0 {
                percent = 0
            } else if percent > 1.0 {
                percent = 1.0
            }
            // calculate time to seek to in video timeline
            let seconds = Float64(percent * totalSeconds)
            let time = CMTimeMakeWithSeconds(seconds, preferredTimescale: currentItem.duration.timescale)
            self.contentView.seek(to: time, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        case .ended, .cancelled, .failed:
            // reset scrubbing begin time
            self.scrubbingBeginTime = nil
            // resume playback after user stops panning
            self.contentView.play()
            
        @unknown default:
            break
        }
    }
    
    @objc private func handle(longPress: UILongPressGestureRecognizer) {
        switch longPress.state {
        case .possible:
            break
        case .began:
            UIView.animate(withDuration: Theme.animationDurationFast) {
                self.contentView.shouldShowOnlyMoment(true)
                self.footerView.alpha = 0.0
            }
            self.contentView.mute()
        case .changed:
            break
        case .ended, .cancelled, .failed:
            UIView.animate(withDuration: Theme.animationDurationFast) {
                self.contentView.shouldShowOnlyMoment(false)
                self.footerView.alpha = 1.0
            }
            self.contentView.unMute()
        @unknown default:
            break
        }
    }
}

extension MomentViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
