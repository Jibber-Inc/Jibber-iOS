//
//  CameraManager.swift
//  Benji
//
//  Created by Benji Dodgson on 10/13/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import AVFoundation
import Vision
import MetalKit
import CoreImage.CIFilterBuiltins
import Lottie
import Localization
import VideoToolbox

/// A view controller that allows a user to capture an image of their face.
/// A live preview of the camera is shown on the main view.
class FaceCaptureViewController: ViewController {

    enum VideoCaptureState {
        case idle
        case starting
        case started
        case capturing
        case ending
    }

    @Published private(set) var videoCaptureState: VideoCaptureState = .idle

    var didCapturePhoto: ((UIImage) -> Void)?
    var didCaptureVideo: ((URL) -> Void)?

    @Published private(set) var hasRenderedFaceImage = false
    @Published private(set) var faceDetected = false
    @Published private(set) var eyesAreClosed = false
    @Published private(set) var isSmiling = false

    private var currentCIImage: CIImage? {
        didSet {
            self.cameraView.draw()
        }
    }
    
    let cameraViewContainer = UIView()

    /// Shows a live preview of what the camera is seeing..
    lazy var cameraView: MetalView = {
        let metalView = MetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        metalView.delegate = self
        metalView.alpha = 0 
        return metalView
    }()

    let videoPreviewView = VideoView()

    let orientation: CGImagePropertyOrientation = .left

    lazy var faceCaptureSession = PhotoVideoCaptureSession()

    /// A request to separate a person from the background in an image.
    private var segmentationRequest = VNGeneratePersonSegmentationRequest()
    private var sequenceHandler = VNSequenceRequestHandler()
    
    let animationView = LottieAnimationView.with(animation: .faceScan)
    let label = ThemeLabel(font: .medium, textColor: .white)
    
    deinit {
        if self.isSessionRunning {
            self.stopSession()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.faceCaptureSession.avCaptureDelegate = self
        
        self.view.addSubview(self.cameraViewContainer)
        self.cameraViewContainer.addSubview(self.cameraView)
        self.cameraViewContainer.layer.borderColor = ThemeColor.B1.color.cgColor
        self.cameraViewContainer.layer.borderWidth = 2
        self.cameraViewContainer.clipsToBounds = true

        self.cameraViewContainer.addSubview(self.videoPreviewView)
        
        self.cameraViewContainer.addSubview(self.animationView)
        self.animationView.loopMode = .loop
        self.animationView.alpha = 0
        
        self.view.addSubview(self.label)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.cameraViewContainer.squaredSize = self.view.height * 0.4
        self.cameraViewContainer.pinToSafeArea(.top, offset: .custom(20))
        self.cameraViewContainer.centerOnX()
        self.cameraViewContainer.layer.cornerRadius = self.cameraViewContainer.height * 0.25
        
        self.animationView.squaredSize = self.cameraViewContainer.height * 0.5
        self.animationView.centerOnXAndY()
        
        self.cameraView.width = self.cameraViewContainer.width
        self.cameraView.height = self.cameraViewContainer.height * 1.25
        self.cameraView.pin(.top)
        self.cameraView.centerOnX()

        self.videoPreviewView.expandToSuperviewSize()

        self.label.setSize(withWidth: Theme.getPaddedWidth(with: self.view.width))
        self.label.match(.top, to: .bottom, of: self.cameraViewContainer, offset: .long)
        self.label.centerOnX()
    }
    
    private var animateTask: Task<Void, Never>?
    
    func animate(text: Localized) {
        self.animateTask?.cancel()
        
        self.animateTask = Task { [weak self] in
            guard let `self` = self else { return }
            
            await UIView.awaitAnimation(with: .fast, animations: {
                self.label.alpha = 0
            })
            
            guard !Task.isCancelled else { return }
            
            self.label.setText(text)
            self.view.layoutNow()
            
            await UIView.awaitAnimation(with: .fast, animations: {
                self.label.alpha = 1.0
            })
        }
    }

    // MARK: - Photo Capture Session

    /// Returns true if the underlaying photo capture session is running.
    var isSessionRunning: Bool {
        return self.faceCaptureSession.isRunning
    }

    /// Starts the face capture session so that we can display the photo preview and capture a photo/video.
    func beginSession() {
        guard !self.isSessionRunning else { return }
        self.faceCaptureSession.begin()
    }
    
    /// Stops the face capture session.
    func stopSession() {
        guard self.isSessionRunning else { return }
        self.faceCaptureSession.stop()
        self.currentCIImage = nil
    }

    func capturePhoto() {
        guard self.isSessionRunning else { return }

        self.captureCurrentImageAsPhoto()
    }

    // MARK: - Video Preview

    func setVideoPreview(with videoURL: URL?) {
        if let videoURL = videoURL {
            self.videoPreviewView.updatePlayer(with: [videoURL])
        } else {
            self.videoPreviewView.updatePlayer(with: [])
        }
    }

    // MARK: - AVAssetWriter Vars

    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    func startVideoCapture() {
        guard self.videoCaptureState == .idle else { return }

        self.videoCaptureState = .starting
    }

    func finishVideoCapture() {
        switch self.videoCaptureState {
        case .starting, .started, .capturing:
            self.videoCaptureState = .ending
        case .idle, .ending:
            // Do nothing
            break
        }
    }
}

extension FaceCaptureViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let detectFaceRequest = VNDetectFaceLandmarksRequest(completionHandler: self.detectedFace)

        do {
            try self.sequenceHandler.perform([detectFaceRequest, self.segmentationRequest],
                                             on: imageBuffer,
                                             orientation: self.orientation)

            // Get the pixel buffer that contains the mask image.
            guard let maskPixelBuffer
                    = self.segmentationRequest.results?.first?.pixelBuffer else { return }
            // Process the images.
            let blendedImage = self.blend(original: imageBuffer, mask: maskPixelBuffer)

            // Set the new, blended image as current.
            self.currentCIImage = blendedImage
        } catch {
            logError(error)
        }

        switch self.videoCaptureState {
        case .idle:
            // Do nothing
            break
        case .starting:
            // Initialize the AVAsset writer to prepare for capture
            self.startAssetWriter()
            self.videoCaptureState = .started
        case .started:
            // Wait for the input to be ready before starting the session
            guard let input = self.videoWriterInput, input.isReadyForMoreMediaData else { break }
            self.startSession(with: sampleBuffer)
            self.writeSampleToFile(sampleBuffer)
            self.videoCaptureState = .capturing
        case .capturing:
            self.writeSampleToFile(sampleBuffer)
        case .ending:
            self.finishWritingVideo()
            self.videoCaptureState = .idle
        }
    }

    /// Makes the image black and white, and makes the background clear.
    func blend(original framePixelBuffer: CVPixelBuffer, mask maskPixelBuffer: CVPixelBuffer) -> CIImage? {
        // Make the background clear.
        let color = CIColor(color: UIColor.clear)

        // Create CIImage objects for the video frame and the segmentation mask.
        let originalImage = CIImage(cvPixelBuffer: framePixelBuffer).oriented(self.orientation)
        var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

        // Scale the mask image to fit the bounds of the video frame.
        let scaleX = originalImage.extent.width / maskImage.extent.width
        let scaleY = originalImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

        let solidColor = CIImage(color: color).cropped(to: maskImage.extent)

        // List of all filters: https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/

        let filter = CIFilter(name: "CIPhotoEffectNoir")
        filter?.setValue(originalImage, forKey: "inputImage")

        guard let bwImage = filter?.outputImage else { return nil }

        // Blend the original, background, and mask images.
        let blendFilter = CIFilter.blendWithRedMask()
        blendFilter.inputImage = bwImage
        blendFilter.backgroundImage = solidColor
        blendFilter.maskImage = maskImage

        return blendFilter.outputImage?.oriented(.leftMirrored)
    }

    private func startAssetWriter() {
        do {
            // Get a url to temporarily store the video
            let uuid = UUID().uuidString
            let url = URL(fileURLWithPath: NSTemporaryDirectory(),
                          isDirectory: true).appendingPathComponent(uuid+".mov")

            // Create an asset writer that will write the video to the url
            self.videoWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
            let settings: [String : Any] = [AVVideoCodecKey : AVVideoCodecType.hevcWithAlpha,
                                            AVVideoWidthKey : 480,
                                           AVVideoHeightKey : 480,
                            AVVideoCompressionPropertiesKey : [AVVideoQualityKey : 0.5,
                                 kVTCompressionPropertyKey_TargetQualityForAlpha : 0.5]
            ]

            self.videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video,
                                                       outputSettings: settings)

            self.videoWriterInput?.mediaTimeScale = CMTimeScale(bitPattern: 600)
            self.videoWriterInput?.expectsMediaDataInRealTime = true

            let pixelBufferAttributes = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: 480,
                kCVPixelBufferHeightKey: 480,
                kCVPixelBufferMetalCompatibilityKey: true] as [String: Any]
            
            guard let writer = self.videoWriter, let input = self.videoWriterInput else { return }

            self.pixelBufferAdaptor
            = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                   sourcePixelBufferAttributes: pixelBufferAttributes)

            if writer.canAdd(input) {
                writer.add(input)
            }

            writer.startWriting()
        } catch {
            logError(error)
        }
    }

    private func startSession(with sampleBuffer: CMSampleBuffer) {
        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        self.videoWriter?.startSession(atSourceTime: startTime)
    }

    private func writeSampleToFile(_ sampleBuffer: CMSampleBuffer) {
        guard let input = self.videoWriterInput,
                input.isReadyForMoreMediaData,
                let currentImage = self.currentCIImage else { return }

        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey : kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey : kCFBooleanTrue] as CFDictionary
        let width = Int(currentImage.extent.width)
        let height = Int(currentImage.extent.width)

        CVPixelBufferCreate(kCFAllocatorDefault,
                            width,
                            height,
                            kCVPixelFormatType_32BGRA,
                            attrs,
                            &pixelBuffer)

        let context = CIContext()
        // Using a magic number (-240) for now. We should figure out the appropriate offset dynamically.
        let transform = CGAffineTransform(translationX: 0, y: -240)
        let adjustedImage = currentImage.transformed(by: transform)
        context.render(adjustedImage, to: pixelBuffer!)

        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let presentationTime = CMTime(seconds: currentTime,
                                      preferredTimescale: CMTimeScale(bitPattern: 600))

        self.pixelBufferAdaptor?.append(pixelBuffer!, withPresentationTime: presentationTime)
    }

    private func finishWritingVideo() {
        self.videoWriterInput?.markAsFinished()
        guard let videoURL = self.videoWriter?.outputURL else { return }
        self.videoWriter?.finishWriting { [unowned self] in
            self.didCaptureVideo?(videoURL)
        }
    }

    private func detectedFace(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNFaceObservation], let _ = results.first else {
            self.faceDetected = false
            return
        }

        self.faceDetected = true
    }
}

extension FaceCaptureViewController: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {

        guard let connection = output.connection(with: .video) else { return }
        connection.automaticallyAdjustsVideoMirroring = true

        self.captureCurrentImageAsPhoto()
    }

    func captureCurrentImageAsPhoto() {
        guard let ciImage = self.currentCIImage else { return }

        // If we find a face in the image, we'll crop around it and store it here.
        var finalCIImage = ciImage

        let imageOptions = NSMutableDictionary(object: NSNumber(value: 5) as NSNumber,
                                               forKey: CIDetectorImageOrientation as NSString)
        imageOptions[CIDetectorEyeBlink] = true
        let accuracy = [CIDetectorAccuracy : CIDetectorAccuracyHigh]
        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: accuracy)
        let faces = faceDetector?.features(in: ciImage, options: imageOptions as? [String : AnyObject])

        if let face = faces?.first as? CIFaceFeature {
            self.eyesAreClosed = face.leftEyeClosed && face.rightEyeClosed
            self.isSmiling = face.hasSmile

            // Increase the bounds around the face so it's not too zoomed in.
            var adjustedFaceBounds = face.bounds
            adjustedFaceBounds.size.height = face.bounds.height * 2.2
            adjustedFaceBounds.size.width = adjustedFaceBounds.height
            adjustedFaceBounds.centerY = face.bounds.centerY + face.bounds.height * 0.2
            adjustedFaceBounds.centerX = face.bounds.centerX

            finalCIImage = ciImage.cropped(to: adjustedFaceBounds)
        } else {
            self.eyesAreClosed = false
            self.isSmiling = false
        }

        // CGImages play nicer with UIKit.
        // Per the docs: "Due to Core Image's coordinate system mismatch with UIKit, this filtering
        // approach may yield unexpected results when displayed in a UIImageView with contentMode."
        let context = CIContext()
        let cgImage = context.createCGImage(finalCIImage, from: finalCIImage.extent)!

        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        self.didCapturePhoto?(image)
    }
}

// MARK: - MTKViewDelegate

extension FaceCaptureViewController: MTKViewDelegate {

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

        if !self.hasRenderedFaceImage {
            Task.onMainActorAsync {
                self.hasRenderedFaceImage = true
                view.alpha = 1.0
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Delegate method not implemented.
    }
}
