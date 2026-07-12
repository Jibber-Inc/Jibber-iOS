//
//  ExpressionVideoView.swift
//  Jibber
//
//  Created by Martin Young on 6/26/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import AVFoundation

class ExpressionVideoView: VideoView {

    var expression: Expression? {
        didSet {
            // Only update the video if this is a new expression.
            guard self.expression != oldValue else { return }

            self.reset()
            self.updatePlayer()
        }
    }
    
    /// The currently running task that loads the video url.
    private var loadTask: Task<Void, Never>?
    
    private func updatePlayer() {
        self.loadTask?.cancel()

        guard let expression = self.expression else {
            self.reset()
            return
        }

        self.loadTask = Task { [weak self] in
            guard let self else { return }
            
            guard let videoURL = try? await expression.file?.retrieveCachedPathURL(),
                  !self.allURLs.contains(videoURL) else { return }

            guard !Task.isCancelled else { return }

            self.updatePlayer(with: [videoURL])
        }
    }
}
