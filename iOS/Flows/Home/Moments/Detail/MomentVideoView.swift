//
//  MomentVideoView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/12/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import AVFoundation
import Foundation
import ParseCore
import Lottie

class MomentVideoView: VideoView {
    
    let animationView = LottieAnimationView.with(animation: .loading)
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.shouldPlay = true 
        self.playerLayer.videoGravity = .resizeAspectFill
        
        self.addSubview(self.animationView)
        self.animationView.loopMode = .loop
    }
    
    func loadPreview(for moment: Moment) {
        guard let preview = moment.preview else { return }
        self.updatePlayer(with: preview)
    }
    
    func loadFullMoment(for moment: Moment) {
        guard let file = moment.file else { return }
        self.updatePlayer(with: file)
    }
    
    /// The currently running task that loads the video url.
    private var loadTask: Task<Void, Never>?
    
    private func updatePlayer(with file: PFFileObject) {
        self.loadTask?.cancel()

        self.loadTask = Task { [weak self] in
            guard let self else { return }
            
            self.animationView.play()
            
            guard let videoURL = try? await file.retrieveCachedPathURL(),
                  !self.allURLs.contains(videoURL) else {
                self.animationView.stop()
                return
            }

            guard !Task.isCancelled else { return }

            self.updatePlayer(with: [videoURL])
            
            self.animationView.stop()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.animationView.squaredSize = 20
        self.animationView.centerOnXAndY()
    }
}
