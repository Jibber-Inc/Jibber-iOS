//
//  CameraManager.swift
//  Benji
//
//  Created by Benji Dodgson on 10/13/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import AVFoundation
import Combine
import CoreVideo
import Vision
import MetalKit
import CoreImage.CIFilterBuiltins
import Lottie
import Localization
import VideoToolbox

private nonisolated struct FaceCaptureFrame: Sendable {
    let generation: UUID
    let image: CIImage
    let faceDetected: Bool
    let presentationTime: CMTime
}

/// Processes capture buffers synchronously on the serial queue supplied by
/// `PhotoVideoCaptureSession`, then publishes only immutable frame results to the main actor.
private nonisolated final class FaceCaptureFrameProcessor: NSObject,
                                                           AVCaptureVideoDataOutputSampleBufferDelegate,
                                                           @unchecked Sendable {

    private let generation: UUID
    private let orientation: CGImagePropertyOrientation
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()
    private let sequenceHandler = VNSequenceRequestHandler()
    private let context = CIContext()
    private let didProcess: @MainActor @Sendable (FaceCaptureFrame) -> Void

    init(generation: UUID,
         orientation: CGImagePropertyOrientation,
         didProcess: @escaping @MainActor @Sendable (FaceCaptureFrame) -> Void) {
        self.generation = generation
        self.orientation = orientation
        self.didProcess = didProcess
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let faceRequest = VNDetectFaceLandmarksRequest()

        do {
            try self.sequenceHandler.perform([faceRequest, self.segmentationRequest],
                                             on: imageBuffer,
                                             orientation: self.orientation)

            guard let maskPixelBuffer = self.segmentationRequest.results?.first?.pixelBuffer,
                  let blendedImage = self.blend(original: imageBuffer,
                                                mask: maskPixelBuffer),
                  let renderedImage = self.context.createCGImage(blendedImage,
                                                                 from: blendedImage.extent) else { return }

            // Rendering to a CGImage eagerly detaches the result from AVFoundation's pooled
            // source and Vision mask pixel buffers before the frame crosses executors.
            let detachedImage = CIImage(cgImage: renderedImage).transformed(
                by: .init(translationX: blendedImage.extent.origin.x,
                          y: blendedImage.extent.origin.y)
            )

            let frame = FaceCaptureFrame(
                generation: self.generation,
                image: detachedImage,
                faceDetected: !(faceRequest.results?.isEmpty ?? true),
                presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            )
            let didProcess = self.didProcess

            // This FIFO dispatch preserves capture-frame order while crossing to UI isolation.
            DispatchQueue.main.async { @MainActor in
                didProcess(frame)
            }
        } catch {
            debugPrint("Face capture frame processing failed:", error)
        }
    }

    /// Makes the image black and white, and makes the background clear.
    private func blend(original framePixelBuffer: CVPixelBuffer,
                       mask maskPixelBuffer: CVPixelBuffer) -> CIImage? {
        let color = CIColor(red: 0, green: 0, blue: 0, alpha: 0)

        let originalImage = CIImage(cvPixelBuffer: framePixelBuffer).oriented(self.orientation)
        var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

        let scaleX = originalImage.extent.width / maskImage.extent.width
        let scaleY = originalImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

        let solidColor = CIImage(color: color).cropped(to: maskImage.extent)
        let filter = CIFilter(name: "CIPhotoEffectNoir")
        filter?.setValue(originalImage, forKey: "inputImage")

        guard let blackAndWhiteImage = filter?.outputImage else { return nil }

        let blendFilter = CIFilter.blendWithRedMask()
        blendFilter.inputImage = blackAndWhiteImage
        blendFilter.backgroundImage = solidColor
        blendFilter.maskImage = maskImage

        return blendFilter.outputImage?.oriented(.leftMirrored)
    }
}

/// A view controller that allows a user to capture an image of their face.
/// A live preview of the camera is shown on the main view.
@MainActor
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
    var didResolveCameraAuthorization: ((AVAuthorizationStatus) -> Void)?
    var didResolveSessionStart: ((Bool) -> Void)?

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

    /// The normal capture screen keeps its historical geometry. Canonical
    /// onboarding embeds the same controller above a composer control row and
    /// lets the camera use that dedicated content area more fully.
    var usesEmbeddedCaptureLayout = false {
        didSet {
            guard usesEmbeddedCaptureLayout != oldValue else { return }
            self.label.isHidden = self.usesEmbeddedCaptureLayout
            self.viewIfLoaded?.setNeedsLayout()
        }
    }

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
    private var frameProcessor: FaceCaptureFrameProcessor?
    private var captureGeneration = UUID()
    
    let animationView = LottieAnimationView.with(animation: .faceScan)
    let label = ThemeLabel(font: .medium, textColor: .white)
    
    isolated deinit {
        self.stopSession()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.faceCaptureSession.didCapturePhoto = { [weak self] in
            self?.captureCurrentImageAsPhoto()
        }
        
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
        self.label.isHidden = self.usesEmbeddedCaptureLayout
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let labelWidth = Theme.getPaddedWidth(with: self.view.width)
        self.label.setSize(withWidth: labelWidth)

        let cameraSize: CGFloat
        if self.usesEmbeddedCaptureLayout {
            let safeHeight = self.view.safeAreaLayoutGuide.layoutFrame.height
            let availableCameraHeight = max(
                0,
                safeHeight - Theme.ContentOffset.custom(20).value
            )
            cameraSize = min(
                min(self.view.width, self.view.height) * 0.82,
                availableCameraHeight
            )
        } else {
            cameraSize = self.view.height * 0.4
        }
        self.cameraViewContainer.squaredSize = cameraSize
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

        if !self.usesEmbeddedCaptureLayout {
            self.label.match(.top, to: .bottom, of: self.cameraViewContainer, offset: .long)
            self.label.centerOnX()
        }
    }
    
    private var animateTask: Task<Void, Never>?
    
    func animate(text: Localized) {
        self.animateTask?.cancel()
        
        self.animateTask = Task { [weak self] in
            guard let self else { return }
            
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

    /// Includes authorization, start, and stop transitions. Re-entry can ask
    /// the session to restart even while an earlier stop is still draining.
    var isSessionActive: Bool {
        return self.faceCaptureSession.isActive
    }

    /// Starts the face capture session so that we can display the photo preview and capture a photo/video.
    func beginSession() {
        // While already authorizing/starting/running, retain the processor that
        // AVCaptureOutput is using. During stopping, install the next processor
        // before asking the session to queue its restart.
        guard !self.faceCaptureSession.isActive
                || self.faceCaptureSession.isStopping else { return }

        self.faceCaptureSession.didResolveAuthorization = { [weak self] status in
            self?.didResolveCameraAuthorization?(status)
        }
        self.faceCaptureSession.didFinishStarting = { [weak self] didStart in
            self?.didResolveSessionStart?(didStart)
        }

        let captureGeneration = UUID()
        let frameProcessor = FaceCaptureFrameProcessor(
            generation: captureGeneration,
            orientation: self.orientation
        ) { [weak self] frame in
            self?.process(frame)
        }
        self.captureGeneration = captureGeneration
        self.frameProcessor = frameProcessor
        self.faceCaptureSession.avCaptureDelegate = frameProcessor
        self.faceCaptureSession.begin()
    }
    
    /// Stops the face capture session.
    func stopSession() {
        self.captureGeneration = UUID()
        self.faceCaptureSession.avCaptureDelegate = nil
        self.faceCaptureSession.stop()
        self.frameProcessor = nil
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

    private static let encodedVideoDimension = 480

    private var videoWriter: AVAssetWriter?
    private var pixelBufferReceiver: AVAssetWriterInput.PixelBufferReceiver?
    private var hasStartedAssetWriterSession = false
    private let videoWriterContext = CIContext()

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

extension FaceCaptureViewController {

    private func process(_ frame: FaceCaptureFrame) {
        guard frame.generation == self.captureGeneration else { return }

        self.faceDetected = frame.faceDetected
        self.currentCIImage = frame.image

        switch self.videoCaptureState {
        case .idle:
            // Do nothing
            break
        case .starting:
            // Initialize the AVAsset writer to prepare for capture
            self.videoCaptureState = self.startAssetWriter() ? .started : .idle
        case .started:
            guard self.startSession(at: frame.presentationTime),
                  self.writeSampleToFile(frame.image,
                                         presentationTime: frame.presentationTime) else { break }
            self.videoCaptureState = .capturing
        case .capturing:
            _ = self.writeSampleToFile(frame.image,
                                       presentationTime: frame.presentationTime)
        case .ending:
            self.finishWritingVideo()
            self.videoCaptureState = .idle
        }
    }

    private func startAssetWriter() -> Bool {
        do {
            // Get a url to temporarily store the video
            let uuid = UUID().uuidString
            let url = URL(fileURLWithPath: NSTemporaryDirectory(),
                          isDirectory: true).appendingPathComponent(uuid+".mov")

            // Create an asset writer that will write the video to the url
            self.videoWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
            let settings: [String : Any] = [AVVideoCodecKey : AVVideoCodecType.hevcWithAlpha,
                                            AVVideoWidthKey : Self.encodedVideoDimension,
                                           AVVideoHeightKey : Self.encodedVideoDimension,
                            AVVideoCompressionPropertiesKey : [AVVideoQualityKey : 0.5,
                                 kVTCompressionPropertyKey_TargetQualityForAlpha : 0.5]
            ]

            let input = AVAssetWriterInput(mediaType: AVMediaType.video,
                                           outputSettings: settings)

            input.mediaTimeScale = CMTimeScale(bitPattern: 600)

            let pixelBufferAttributes = CVPixelBufferCreationAttributes(
                pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
                size: CVImageSize(width: Self.encodedVideoDimension,
                                  height: Self.encodedVideoDimension),
                compatibility: [.metalTexture]
            )
            
            guard let writer = self.videoWriter else { return false }

            self.pixelBufferReceiver = writer.inputPixelBufferReceiver(
                for: input,
                pixelBufferAttributes: pixelBufferAttributes
            )
            try writer.start()
            self.hasStartedAssetWriterSession = false
            return true
        } catch {
            logError(error)
            self.pixelBufferReceiver = nil
            self.videoWriter = nil
            self.hasStartedAssetWriterSession = false
            return false
        }
    }

    private func startSession(at presentationTime: CMTime) -> Bool {
        guard let videoWriter = self.videoWriter,
              videoWriter.status == .writing else { return false }

        guard !self.hasStartedAssetWriterSession else { return true }

        videoWriter.startSession(atSourceTime: presentationTime)
        self.hasStartedAssetWriterSession = true
        return true
    }

    private func writeSampleToFile(_ currentImage: CIImage,
                                   presentationTime: CMTime) -> Bool {
        guard let receiver = self.pixelBufferReceiver else { return false }

        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey : kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey : kCFBooleanTrue,
                     kCVPixelBufferMetalCompatibilityKey : kCFBooleanTrue] as CFDictionary
        let dimension = Self.encodedVideoDimension

        let result = CVPixelBufferCreate(kCFAllocatorDefault,
                                         dimension,
                                         dimension,
                                         kCVPixelFormatType_32BGRA,
                                         attrs,
                                         &pixelBuffer)
        guard result == kCVReturnSuccess, let pixelBuffer else { return false }

        let sourceExtent = currentImage.extent
        guard !sourceExtent.isEmpty else { return false }

        let outputDimension = CGFloat(dimension)
        let outputBounds = CGRect(x: 0,
                                  y: 0,
                                  width: outputDimension,
                                  height: outputDimension)
        let normalizedImage = currentImage.transformed(
            by: .init(translationX: -sourceExtent.minX,
                      y: -sourceExtent.minY)
        )
        let scale = max(outputDimension / sourceExtent.width,
                        outputDimension / sourceExtent.height)
        let scaledImage = normalizedImage.transformed(by: .init(scaleX: scale, y: scale))
        let centeredImage = scaledImage.transformed(
            by: .init(translationX: (outputDimension - scaledImage.extent.width) * 0.5,
                      y: (outputDimension - scaledImage.extent.height) * 0.5)
        ).cropped(to: outputBounds)

        self.videoWriterContext.render(centeredImage,
                                       to: pixelBuffer,
                                       bounds: outputBounds,
                                       colorSpace: CGColorSpaceCreateDeviceRGB())

        let normalizedPresentationTime = CMTime(seconds: presentationTime.seconds,
                                                preferredTimescale: CMTimeScale(bitPattern: 600))

        do {
            let readOnlyPixelBuffer = CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer)
            return try receiver.appendImmediately(readOnlyPixelBuffer,
                                                  with: normalizedPresentationTime)
        } catch {
            logError(error)
            return false
        }
    }

    private func finishWritingVideo() {
        self.pixelBufferReceiver?.finish()
        guard let writer = self.videoWriter else {
            self.pixelBufferReceiver = nil
            self.hasStartedAssetWriterSession = false
            return
        }

        let videoURL = writer.outputURL
        self.pixelBufferReceiver = nil
        self.videoWriter = nil
        self.hasStartedAssetWriterSession = false

        writer.finishWriting { [weak self] in
            Task { @MainActor [weak self] in
                self?.didCaptureVideo?(videoURL)
            }
        }
    }

}

extension FaceCaptureViewController {

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
