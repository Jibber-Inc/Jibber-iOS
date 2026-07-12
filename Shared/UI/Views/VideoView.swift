//
//  VideoView.swift
//  Jibber
//
//  Created by Martin Young on 6/27/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import UIKit
import AVFoundation
import Combine

class VideoView: BaseView {
    
    var shouldPlayAudio: Bool = true {
        didSet {
            guard let player = self.playerLayer.player else { return }
            player.volume = self.shouldPlayAudio ? 1.0 : 0.0 
        }
    }
    
    var shouldPlay: Bool = false {
        didSet {
            guard let player = self.playerLayer.player else { return }
            
            if self.shouldPlay, !self.isPlaying {
                player.playImmediately(atRate: 1.0)
            } else if !self.shouldPlay, self.isPlaying {
                player.pause()
            }
        }
    }
        
    @Published var isPlaying: Bool = false

    let playerLayer = AVPlayerLayer(player: nil)
    /// An object that keeps looping the video back to the beginning.
    private(set) var looper: AVPlayerLooper?
    
    private(set) var allURLs: [URL] = []
    
    override func initializeSubviews() {
        super.initializeSubviews()

        // Keep the isPlaying status up to date by monitoring rateDidChange notifications
        NotificationCenter.default.publisher(for: AVPlayer.rateDidChangeNotification)
            .filter({ [unowned self] notification in
                if let player = notification.object as? AVPlayer,
                   player === self.playerLayer.player {
                    return true
                }
                
                return false
            }).mainSink { [unowned self] (value) in
                guard let player = value.object as? AVQueuePlayer else { return }
                self.isPlaying = player.timeControlStatus == .playing
            }.store(in: &self.cancellables)

        // Keep track of app foreground events so we can restart the player if necessary.
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification).mainSink { [weak self] _ in
            guard let self else { return }
            guard let player = self.playerLayer.player else { return }

            if self.shouldPlay, !self.isPlaying, self.alpha != 0 {
                player.playImmediately(atRate: 1.0)
            }
            
        }.store(in: &self.cancellables)

        // Initialize views
        self.layer.addSublayer(self.playerLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.playerLayer.frame = self.bounds
    }
    
    func reset() {
        self.updatePlayer(with: [])
    }

    // MARK: - Video Setting

    /// A task for loading a video track from a url.
    private var loadTracksTask: Task<Void, Never>?

    func updatePlayer(with urls: [URL]) {
        self.loadTracksTask?.cancel()
        
        self.allURLs = urls

        guard !urls.isEmpty else {
            // Stop playback if the url is nil.
            self.playerLayer.player = nil
            self.looper = nil 
            return
        }

        self.loadTracksTask = Task { [weak self] in
            var videoItems: [AVPlayerItem] = []
            
            await urls.asyncForEach { videoURL in
                // Retrieve the video asset.
                let asset = AVURLAsset(url: videoURL)
                
                guard let tracks = try? await asset.loadTracks(withMediaType: .video), !Task.isCancelled else { return }

                // We will only have one video track, so the first one is the one we want.
                guard let videoAsset = tracks.first?.asset else { return }
                
                let videoItem = AVPlayerItem(asset: videoAsset)
                
                videoItems.append(videoItem)
            }
            
            if let player = self?.playerLayer.player, videoItems.count == 1 {
                // No need to create a new player if we already have one. Just update the video.
                player.replaceCurrentItem(with: videoItems.first)
            } else {
                // If no player exists, create a new one and assign it the downloaded videos.
                let player = AVQueuePlayer(items: videoItems)
                player.automaticallyWaitsToMinimizeStalling = false
                self?.playerLayer.player = player
            }
            
            guard let player = self?.playerLayer.player as? AVQueuePlayer else { return }
            
            // If we only have one item, use the built in looper
            if videoItems.count == 1, let first = videoItems.first {
                self?.looper = AVPlayerLooper(player: player, templateItem: first)
            } else if videoItems.count > 1 {
                // Otherwise subscribe to updates to force a loop
                self?.subsribeToPlayerUpdates()
            }
            
            if self?.shouldPlay == true {
                player.playImmediately(atRate: 1.0)
            }
            
            if let audio = self?.shouldPlayAudio {
                player.volume = audio ? 1.0 : 0.0
            }
        }
    }
    
    private var token: NSKeyValueObservation?
    
    private func subsribeToPlayerUpdates() {
        self.token?.invalidate()
        
        self.token = self.playerLayer.player?.observe(\.currentItem) { [weak self] player, _ in
            guard let quePlayer = player as? AVQueuePlayer else { return }

            guard quePlayer.items().count == 1 else { return }

            Task { @MainActor [weak self] in
                self?.reAddURLsToCurrentPlayerIfNeeded()
            }
        }
    }

    private func reAddURLsToCurrentPlayerIfNeeded() {
        guard let player = self.playerLayer.player as? AVQueuePlayer,
              player.items().count == 1 else { return }

        self.reAddURLs(to: player)
    }
    
    private func reAddURLs(to player: AVQueuePlayer) {
        self.allURLs.forEach({ url in
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            player.insert(item, after: player.items().last)
        })
    }
}
