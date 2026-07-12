//
//  FrontPreviewVideoView.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/4/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Lottie
import MetalKit
import AVKit

class FrontPreviewVideoView: VideoPreviewView {
    
    private let emotionGradientView = EmotionGradientView()
    
    var animationDidEnd: CompletionOptional = nil
    
    var animation = CABasicAnimation(keyPath: "strokeEnd")
    
    private(set) var isAnimating: Bool = false
    private(set) var isPlayback: Bool = false
    
    lazy var shapeLayer: CAShapeLayer = {
        let shapeLayer = CAShapeLayer()
        let color = ThemeColor.D6.color.cgColor
        shapeLayer.fillColor = ThemeColor.clear.color.cgColor
        shapeLayer.strokeColor = color
        shapeLayer.lineCap = .round
        shapeLayer.lineWidth = 4
        shapeLayer.shadowColor = color
        shapeLayer.shadowRadius = 5
        shapeLayer.shadowOffset = .zero
        shapeLayer.shadowOpacity = 1.0
        return shapeLayer
    }()
    
    /// Shows a live preview of what the camera is seeing..
    lazy var cameraView: MetalView = {
        let metalView = MetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        metalView.delegate = self
        return metalView
    }()
    
    private(set) var currentCIImage: CIImage? {
        didSet {
            self.cameraView.draw()
        }
    }
    
    override func initializeSubviews() {
        super.initializeSubviews()
        
        self.insertSubview(self.emotionGradientView, at: 0)
        self.emotionGradientView.alpha = 0.75
        
        self.addSubview(self.cameraView)
        
        self.layer.borderColor = ThemeColor.whiteWithAlpha.color.cgColor
        self.layer.borderWidth = 2
        
        self.clipsToBounds = true
        
        self.playbackView.$isPlaying.mainSink { [unowned self] isPlaying in
            guard isPlaying, let duration = self.playbackView.playerLayer.player?.currentItem?.duration else { return }
            
            self.startPlaybackAnimation(with: duration)
        }.store(in: &self.cancellables)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.emotionGradientView.expandToSuperviewSize()
        
        self.cameraView.width = self.width
        self.cameraView.height = self.height * 1.25
        self.cameraView.pin(.top)
        self.cameraView.centerOnX()
                
        self.layer.cornerRadius = self.height * 0.25
    }
    
    func startRecordingAnimation() {
    
        self.shapeLayer.removeFromSuperlayer()
        self.layer.addSublayer(self.shapeLayer)
                
        self.animation.delegate = self
        self.animation.fromValue = 0
        self.animation.duration = MomentCaptureViewController.maxDuration
        self.animation.isRemovedOnCompletion = false
        self.animation.fillMode = .forwards
        
        self.shapeLayer.path = UIBezierPath(roundedRect: self.bounds,
                                            byRoundingCorners: [.allCorners],
                                            cornerRadii: CGSize(width: self.height * 0.25, height: self.height * 0.25)).cgPath
    
        self.shapeLayer.add(self.animation, forKey: "MyAnimation")
    }
    
    func stopRecordingAnimation() {
        self.shapeLayer.removeAllAnimations()
        self.shapeLayer.removeFromSuperlayer()
    }
    
    /// Makes the image black and white, and makes the background clear.
    func setImage(original framePixelBuffer: CVPixelBuffer, mask maskPixelBuffer: CVPixelBuffer) {
        // Make the background clear.
        let color = CIColor(color: UIColor.clear)

        // Create CIImage objects for the video frame and the segmentation mask.
        let originalImage = CIImage(cvPixelBuffer: framePixelBuffer).oriented(.left)
        var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

        // Scale the mask image to fit the bounds of the video frame.
        let scaleX = originalImage.extent.width / maskImage.extent.width
        let scaleY = originalImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

        let solidColor = CIImage(color: color).cropped(to: maskImage.extent)

        // Blend the original, background, and mask images.
        let blendFilter = CIFilter.blendWithRedMask()
        blendFilter.inputImage = originalImage
        blendFilter.backgroundImage = solidColor
        blendFilter.maskImage = maskImage

        self.currentCIImage = blendFilter.outputImage?.oriented(.leftMirrored)
    }
    
    private func startPlaybackAnimation(with duration: CMTime) {
        
        self.shapeLayer.removeFromSuperlayer()
        self.layer.addSublayer(self.shapeLayer)
                
        self.animation.delegate = nil 
        self.animation.fromValue = 0.01
        self.animation.duration = duration.seconds
        self.animation.isRemovedOnCompletion = false
        self.animation.fillMode = .forwards
        self.animation.repeatCount = Float.greatestFiniteMagnitude
        
        self.shapeLayer.path = UIBezierPath(roundedRect: self.bounds,
                                            byRoundingCorners: [.allCorners],
                                            cornerRadii: CGSize(width: self.height * 0.25, height: self.height * 0.25)).cgPath
    
        self.shapeLayer.add(self.animation, forKey: "MyAnimation")
    }
    
    // Overriding because changing the alpha on the preivew layer, hides the entire view.
    override func beginPlayback(with url: URL) {
        self.isPlayback = true
        
        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.cameraView.alpha = 0.0
            self.playbackView.alpha = 1.0
        } completion: { _ in
            self.playbackView.shouldPlay = true
            self.playbackView.updatePlayer(with: [url])
            
        }
    }
    
    override func stopPlayback() {
        self.stopRecordingAnimation() 
        self.playbackView.reset()
        self.isPlayback = false
        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.playbackView.alpha = 0.0
            self.cameraView.alpha = 1.0
        }
    }
}

extension FrontPreviewVideoView: CAAnimationDelegate {
    
    func animationDidStart(_ anim: CAAnimation) {
        self.isAnimating = true
    }
    
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        self.isAnimating = false
        
        guard !self.isPlayback else { return }
        self.animationDidEnd?()
    }
}

// MARK: - MTKViewDelegate

 extension FrontPreviewVideoView: MTKViewDelegate {

     func draw(in view: MTKView) {
         guard let metalView = view as? MetalView else { return }

         // grab command buffer so we can encode instructions to GPU
         guard let commandBuffer = metalView.commandQueue.makeCommandBuffer() else {
             return
         }

         // grab image
         guard let ciImage = self.currentCIImage else { return }

         // ensure drawable is free and not tied in the previous drawing cycle
         guard let currentDrawable = view.currentDrawable else { return }

         // Make sure the image is full screen (Aspect fill).
         let drawSize = self.cameraView.drawableSize
         var scaleX = drawSize.width / ciImage.extent.width
         var scaleY = drawSize.height / ciImage.extent.height

         if scaleX > scaleY {
             scaleY = scaleX
         } else {
             scaleX = scaleY
         }

         let newImage = ciImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

         // Render into the metal texture
         metalView.context.render(newImage,
                                  to: currentDrawable.texture,
                                  commandBuffer: commandBuffer,
                                  bounds: newImage.extent,
                                  colorSpace: CGColorSpaceCreateDeviceRGB())

         // register drawable to command buffer
         commandBuffer.present(currentDrawable)
         commandBuffer.commit()
     }

     func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
         // Delegate method not implemented.
     }
 }
