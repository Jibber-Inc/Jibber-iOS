//
//  MomentConfirmationView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/23/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie
import ParseCore
import AVKit
import KeyboardManager

class MomentConfirmationView: BaseView {
    
    let preview = VideoView()
    
    let circle = BaseView()
    let progressView = UIProgressView()
    let label = ThemeLabel(font: .medium)
    let captionTextView = CaptionTextView()
    
    let button = ThemeButton()
    
    let locationToggle = LocationToggleView()
        
    private var savedMoment: Moment?
    
    var didTapFinish: CompletionOptional = nil
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.addSubview(self.circle)
        
        if let window = UIWindow.topWindow() {
            self.circle.squaredSize = window.height * 1.25
            self.circle.layer.cornerRadius = circle.halfHeight
        }
        
        self.circle.set(backgroundColor: .D1)
        self.circle.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
        self.circle.alpha = 0
        
        self.addSubview(self.preview)
        self.preview.shouldPlay = true
        self.preview.shouldPlayAudio = false
        self.preview.alpha = 0
        self.preview.layer.cornerRadius = Theme.cornerRadius
        self.preview.layer.masksToBounds = true
        self.preview.clipsToBounds = true
        self.preview.playerLayer.videoGravity = .resizeAspectFill
        
        self.addSubview(self.label)
        self.label.textAlignment = .center
        self.label.alpha = 0
        
        self.addSubview(self.progressView)
        self.progressView.progressTintColor = ThemeColor.D6.color
        self.progressView.alpha = 0
        
        self.addSubview(self.button)
        self.button.set(style: .custom(color: .white, textColor: .B0, text: "Finished"))
        self.button.alpha = 0
        
        self.addSubview(self.captionTextView)
        
        self.addSubview(self.locationToggle)
        
        self.button.didSelect { [unowned self] in
            Task {
                await self.updateMomentIfNeeded()
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.circle.centerOnXAndY()
        
        self.preview.width = self.width * 0.4
        self.preview.height = self.preview.width * 1.5
        self.preview.centerOnX()
        self.preview.pinToSafeAreaTop()
        
        self.progressView.width = self.preview.width
        self.progressView.centerOnX()
        self.progressView.match(.top, to: .bottom, of: self.preview, offset: .standard)
        
        self.label.setSize(withWidth: self.width)
        self.label.centerOnX()
        self.label.match(.top, to: .top, of: self.progressView)
        
        self.button.setSize(with: self.width)
        self.button.pinToSafeAreaBottom()
        self.button.centerOnX()
        
        self.captionTextView.width = self.button.width
        self.captionTextView.height = self.button.height.doubled
        self.captionTextView.centerOnX()
        self.captionTextView.match(.top, to: .bottom, of: self.label, offset: .long)

        self.locationToggle.match(.bottom, to: .top, of: self.button, offset: .negative(.xtraLong))
        self.locationToggle.centerOnX()
    }
    
    func updateMomentIfNeeded() async {
        guard let moment = self.savedMoment else {
            self.didTapFinish?()
            return
        }
        
        let location = PFGeoPoint(location: LocationManager.shared.currentLocation)
        let caption = self.captionTextView.text
        
        moment.location = location
        moment.caption = caption
        await self.button.handleLoadingState()
        _ = try? await moment.saveToServer()
        await self.button.handleEvent(status: .complete)
        self.didTapFinish?()
    }
    
    func uploadMoment(from recording: PiPRecording, caption: String?) async {
        
        await UIView.awaitSpringAnimation(with: .slow, animations: {
            self.circle.transform = .identity
            self.circle.alpha = 1.0
        })
        
        if let url = recording.backRecordingURL {
            self.preview.updatePlayer(with: [url])
        }
                        
        await UIView.awaitSpringAnimation(with: .fast, animations: {
            self.progressView.alpha = 1.0
            self.preview.alpha = 1.0
        })
        
        do {
            //async let creation: () = Task.sleep(seconds: 1.0)
            async let creation: () = try await self.createMoment(from: recording,
                                                                 location: LocationManager.shared.currentLocation,
                                                                 caption: caption)
            self.progressView.setProgress(0.9, animated: true)
            
            let _ = try await [creation]
            
            self.progressView.setProgress(1.0, animated: true)
            
            await UIView.awaitSpringAnimation(with: .standard, delay: 0.25, animations: {
                self.progressView.alpha = 0
            })
            
            self.label.setText("Success!")
            self.label.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
            self.layoutNow()
            
            await UIView.awaitSpringAnimation(with: .standard, delay: 0.25, animations: {
                self.label.transform = .identity
                self.label.alpha = 1.0
                self.button.alpha = 1.0
                self.locationToggle.alpha = 1.0
                self.captionTextView.alpha = 1.0
            })
            
            await Task.sleep(seconds: 2.0)
            
            await UIView.awaitSpringAnimation(with: .standard, animations: {
                self.label.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
                self.label.alpha = 0.0
            })
            
        } catch {
            
            await UIView.awaitSpringAnimation(with: .fast, animations: {
                self.label.alpha = 0
                self.label.transform = CGAffineTransform(scaleX: 0.001, y: 0.001)
                self.progressView.alpha = 0
            })
            
            self.label.setText("Error")
            self.layoutNow()
            
            await UIView.awaitAnimation(with: .standard, animations: {
                self.label.transform = .identity
                self.label.alpha = 1.0
            })
            
            logError(error)
        }
    }
    
    private func createMoment(from recording: PiPRecording,
                              location: CLLocation?,
                              caption: String?) async throws {
        do {
            let locationToSave: CLLocation? = self.locationToggle.isON ? location : nil
            //Add Weather
            self.savedMoment = try await MomentsStore.shared.createMoment(from: recording,
                                                                          location: locationToSave,
                                                                          caption: caption)
        } catch {
            throw ClientError.error(error: error)
        }
    }
}
