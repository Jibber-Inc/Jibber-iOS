//
//  MomentConfirmationView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/23/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie
import Parse

class MomentConfirmationView: BaseView {
    
    let preview = VideoView()
    
    let circle = BaseView()
    let progressView = UIProgressView()
    let label = ThemeLabel(font: .medium)
    
    let button = ThemeButton()
    
    let locationButton = ThemeButton()
    
    private var savedMoment: Moment?
    
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
        self.preview.backgroundColor = .red
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
        
        self.addSubview(self.locationButton)
        self.locationButton.set(style: .custom(color: .whiteWithAlpha, textColor: .white, text: "Add Location"))
        self.locationButton.alpha = 0
        self.locationButton.didSelect { [unowned self] in
            if LocationManager.shared.isAuthorized {
                LocationManager.shared.requestCurrentLocation()
            } else {
                LocationManager.shared.requestAuthorization()
            }
        }
        
        self.button.didSelect { [unowned self] in
          // update moment
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.circle.centerOnXAndY()
        
        self.preview.width = self.width * 0.33
        self.preview.height = self.preview.width * 1.5
        self.preview.centerOnX()
        self.preview.centerY = self.height * 0.15
        
        self.progressView.width = self.preview.width
        self.progressView.centerOnX()
        self.progressView.match(.top, to: .bottom, of: self.preview, offset: .standard)
        
        self.label.setSize(withWidth: self.width)
        self.label.centerOnX()
        self.label.match(.top, to: .top, of: self.progressView)
        
        self.button.setSize(with: self.width)
        self.button.pinToSafeAreaBottom()
        self.button.centerOnX()
        
        self.locationButton.setSize(with: self.width)
        self.locationButton.match(.bottom, to: .top, of: self.button, offset: .negative(.standard))
        self.locationButton.centerOnX()
    }
    
    func updateMoment() async {
        guard let moment = self.savedMoment else { return }
        moment.location = PFGeoPoint(location: LocationManager.shared.currentLocation)
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
//             async let creation: () = await try self.createMoment(from: recording,
//                                                                  location: LocationManager.shared.currentLocation,
//                                                                  caption: caption)
            async let creation: () = await Task.sleep(seconds: 2.0)
            
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
                self.locationButton.alpha = 1.0
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
            self.savedMoment = try await MomentsStore.shared.createMoment(from: recording,
                                                                          location: location,
                                                                          caption: caption)
        } catch {
            throw ClientError.error(error: error)
        }
    }
}
