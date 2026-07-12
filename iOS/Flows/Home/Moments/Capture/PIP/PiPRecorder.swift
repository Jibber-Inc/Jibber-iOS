//
//  PiPRecorder.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/3/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import AVFoundation
import VideoToolbox

struct PiPRecording: Swift.Sendable {
    var frontRecordingURL: URL?
    var backRecordingURL: URL?
    var previewURL: URL?
}

/// AVFoundation supplies these as property-list dictionaries. The settings and
/// recorder are both main-actor confined.
struct PiPAssetWriterSettings {
    let backVideo: [String: Any]?
    let audio: [String: Any]?
}

/// A uniquely owned copy used synchronously to satisfy the iOS 27 receiver's
/// consuming initializer. This value never leaves the main actor or outlives
/// the capture callback.
struct SynchronousPiPRecorderSample: @unchecked Sendable {
    var buffer: CMSampleBuffer
}

@MainActor
final class PiPRecorder {
    
    private var frontAssetWriter: AVAssetWriter?
    private var frontVideoReceiver: AVAssetWriterInput.PixelBufferReceiver?
    
    private var backAssetWriter: AVAssetWriter?
    private var backVideoReceiver: AVAssetWriterInput.SampleBufferReceiver?
    
    private var audioReceiver: AVAssetWriterInput.SampleBufferReceiver?
    
    private let frontVideoSettings: [String: Any] = [AVVideoCodecKey : AVVideoCodecType.hevcWithAlpha,
                                                     AVVideoWidthKey : 480,
                                                    AVVideoHeightKey : 480,
                                     AVVideoCompressionPropertiesKey : [AVVideoQualityKey : 0.5,
                                          kVTCompressionPropertyKey_TargetQualityForAlpha : 0.5]]
    
    private var backVideoSettings: [String: Any]?
    private var audioSettings: [String: Any]?
    
    private let pixelBufferAttributes = CVPixelBufferCreationAttributes(
        pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
        size: CVImageSize(width: 480, height: 480),
        compatibility: [.metalTexture]
    )
    
    private let ciContext = CIContext()

    private var isReadyToRecord: Bool = false
    private var hasWrittenFirstFrontVideoFrame: Bool = false
    private var startTime: CMTime?
    private var lastFrontVideoTime: CMTime?
    private var lastBackVideoTime: CMTime?
    private var lastAudioTime: CMTime?
    
    deinit {
        FileManager.clearTmpDirectory()
    }
    
    // MARK: - PUBLIC
    
    func initialize(settings: PiPAssetWriterSettings) {
        self.reset()

        self.backVideoSettings = settings.backVideo
        self.audioSettings = settings.audio
        self.initializeFront()
        self.initializeBack()
        self.initializeAudio()
        
        self.isReadyToRecord = true
    }
    
    // MARK: - RECORDING
    
    func startRecording(sample: consuming SynchronousPiPRecorderSample,
                        isVideoOutput: Bool,
                        isFrontVideoOutput: Bool,
                        image: CIImage?) {
        guard self.isReadyToRecord else { return }

        let readySampleBuffer = CMReadySampleBuffer(unsafeBuffer: sample.buffer)

        if isVideoOutput {
            if isFrontVideoOutput {
                self.recordFrontVideo(at: readySampleBuffer.presentationTimeStamp, image: image)
            } else {
                self.recordBackVideo(sampleBuffer: readySampleBuffer)
            }
        } else {
            self.recordAudio(sampleBuffer: readySampleBuffer)
        }
    }

    private func recordFrontVideo(at presentationTime: CMTime, image: CIImage?) {
        guard self.isReadyToRecord, let assetWriter = self.frontAssetWriter else { return }

        if assetWriter.status == .unknown {
            self.startTime = presentationTime
            self.startWritingSession(with: assetWriter, startTime: presentationTime)
            self.handleFrontInput(at: presentationTime, image: image)
        } else if assetWriter.status == .writing {
            self.handleFrontInput(at: presentationTime, image: image)
        }
    }

    private func recordBackVideo(sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) {
        guard self.isReadyToRecord, let assetWriter = self.backAssetWriter else { return }
        
        if assetWriter.status == .unknown {
            if let startTime = self.startTime, self.hasWrittenFirstFrontVideoFrame {
                self.startWritingSession(with: assetWriter, startTime: startTime)
                self.handleBackInput(from: sampleBuffer)
            }
        } else if assetWriter.status == .writing {
            self.handleBackInput(from: sampleBuffer)
        }
    }
    
    private func recordAudio(sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) {
        guard self.isReadyToRecord,
                let assetWriter = self.frontAssetWriter,
                self.hasWrittenFirstFrontVideoFrame else { return }

        // To avoid starting the front asset writer twice, audio samples will NOT trigger the writer to start.
        if assetWriter.status == .writing {
            self.handleAudioInput(from: sampleBuffer)
        }
    }
    
    // MARK: - STOP RECORDING
    
    private var stopRecordingTask: Task<PiPRecording, Error>?

    // This cant be called more than once per recording otherwise inputs will crash
    func stopRecording() async throws -> PiPRecording {
        // If finalization has already started, share its result.
        if let finishVideoTask = self.stopRecordingTask {
            return try await finishVideoTask.value
        }

        // Prevent queued capture callbacks from appending while the writers finish.
        self.isReadyToRecord = false

        // Otherwise start a single finalization task and wait for it to finish.
        self.stopRecordingTask = Task {
            let frontURL = try await self.stopRecordingFront()
            let backURL = try await self.stopRecordingBack()
            let previewURL = await self.compressVideo(for: backURL)
            return PiPRecording(frontRecordingURL: frontURL,
                                backRecordingURL: backURL,
                                previewURL: previewURL)
        }

        do {
            return try await self.stopRecordingTask!.value
        } catch {
            // Dispose of the task because it failed, then pass the error along.
            self.stopRecordingTask = nil
            throw error
        }
    }
    
    // MARK: - PRIVATE
    
    private func reset() {
        FileManager.clearTmpDirectory()
        self.stopRecordingTask = nil
        self.frontAssetWriter = nil
        self.frontVideoReceiver = nil
        self.backAssetWriter = nil
        self.backVideoReceiver = nil
        self.audioReceiver = nil
        self.isReadyToRecord = false
        self.startTime = nil
        self.hasWrittenFirstFrontVideoFrame = false
        self.lastFrontVideoTime = nil
        self.lastBackVideoTime = nil
        self.lastAudioTime = nil
    }
    
    // MARK: - INITIALZE WRITERS/INPUTS
    
    private func initializeFront() {
        // Create an asset writer that records to a temporary file
        let outputFileName = NSUUID().uuidString + "front"
        let outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(outputFileName)
            .appendingPathExtension("mov")

        guard let assetWriter = try? AVAssetWriter(url: outputFileURL, fileType: .mov) else { return }
        
        // Add a video input
        let assetWriterVideoInput = AVAssetWriterInput(mediaType: .video,
                                                       outputSettings: self.frontVideoSettings)
        assetWriterVideoInput.mediaTimeScale = CMTimeScale(bitPattern: 600)
        
        self.frontAssetWriter = assetWriter
        self.frontVideoReceiver = assetWriter.inputPixelBufferReceiver(
            for: assetWriterVideoInput,
            pixelBufferAttributes: self.pixelBufferAttributes
        )
    }
    
    private func initializeBack() {
        // Create an asset writer that records to a temporary file
        let outputFileName = NSUUID().uuidString + "back"
        let outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(outputFileName)
            .appendingPathExtension("mov")

        guard let assetWriter = try? AVAssetWriter(url: outputFileURL, fileType: .mov),
              let settings = self.backVideoSettings else {
            return
        }

        // Add a video input
        let assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)

        self.backAssetWriter = assetWriter
        self.backVideoReceiver = assetWriter.inputReceiver(for: assetWriterVideoInput)
    }
    
    private func initializeAudio() {
        guard let settings = self.audioSettings,
              let frontAssetWriter = self.frontAssetWriter,
              self.audioReceiver.isNil else {
            return
        }

        // Add an audio input
        let assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        self.audioReceiver = frontAssetWriter.inputReceiver(for: assetWriterAudioInput)
    }
    
    private func startWritingSession(with writer: AVAssetWriter,
                                     startTime: CMTime) {
        do {
            try writer.start()
            writer.startSession(atSourceTime: startTime)
        } catch {
            logError(error)
        }
    }
    
    // MARK: - HANDLE SAMPLE BUFFERS
    
    private func handleFrontInput(at currentTime: CMTime, image: CIImage?) {
        guard let receiver = self.frontVideoReceiver,
              let currentImage = image,
              self.shouldAppend(currentTime, after: self.lastFrontVideoTime) else { return }
        
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

        // Using a magic number (-240) for now. We should figure out the appropriate offset dynamically.
        let transform = CGAffineTransform(translationX: 0, y: -240)
        let adjustedImage = currentImage.transformed(by: transform)
        guard let pixelBuffer else { return }
        self.ciContext.render(adjustedImage, to: pixelBuffer)

        do {
            let readOnlyPixelBuffer = CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer)
            if try receiver.appendImmediately(readOnlyPixelBuffer, with: currentTime) {
                self.lastFrontVideoTime = currentTime
                self.hasWrittenFirstFrontVideoFrame = true
            }
        } catch {
            logError(error)
        }
    }
    
    private func handleBackInput(from sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) {
        let currentTime = sampleBuffer.presentationTimeStamp
        guard let receiver = self.backVideoReceiver,
              self.hasWrittenFirstFrontVideoFrame,
              self.shouldAppend(currentTime, after: self.lastBackVideoTime) else { return }

        do {
            if try receiver.appendImmediately(sampleBuffer) {
                self.lastBackVideoTime = currentTime
            }
        } catch {
            logError(error)
        }
    }
    
    private func handleAudioInput(from sampleBuffer: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>) {
        let currentTime = sampleBuffer.presentationTimeStamp
        guard let receiver = self.audioReceiver,
              self.hasWrittenFirstFrontVideoFrame,
              self.shouldAppend(currentTime, after: self.lastAudioTime) else { return }

        do {
            if try receiver.appendImmediately(sampleBuffer) {
                self.lastAudioTime = currentTime
            }
        } catch {
            logError(error)
        }
    }

    private func shouldAppend(_ time: CMTime, after lastTime: CMTime?) -> Bool {
        guard time.isValid,
              let startTime = self.startTime,
              CMTimeCompare(time, startTime) >= 0 else { return false }
        guard let lastTime else { return true }
        return CMTimeCompare(time, lastTime) > 0
    }
    
    // MARK: - STOP RECORDING 
    
    private func stopRecordingFront() async throws -> URL {
        guard let writer = self.frontAssetWriter else {
            throw ClientError.apiError(detail: "No front asset writer")
        }

        if writer.status == .writing {
            self.frontVideoReceiver?.finish()
            self.audioReceiver?.finish()
            await writer.finishWriting()
            return writer.outputURL
        } else {
            throw ClientError.apiError(detail: "Front Failied \(writer.status)")
        }
    }
    
    private func stopRecordingBack() async throws -> URL {
        guard let writer = self.backAssetWriter else {
            throw ClientError.apiError(detail: "No front asset writer")
        }

        if writer.status == .writing {
            self.backVideoReceiver?.finish()
            await writer.finishWriting()
            return writer.outputURL
        } else {
            throw ClientError.apiError(detail: "Back Failed \(writer.status)")
        }
    }
    
    // MARK: - COMPRESSING
    
    private func compressVideo(for inputURL: URL?) async -> URL? {
        guard let inputURL = inputURL else {
            return nil 
        }

        let urlAsset = AVURLAsset(url: inputURL, options: nil)
        
        let outputFileName = NSUUID().uuidString + "preview"
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName).appendingPathExtension("mp4")
        
        guard let exportSession = AVAssetExportSession(asset: urlAsset,
                                                       presetName: AVAssetExportPresetLowQuality) else {
            return nil
        }
        
        do {
            try await exportSession.export(to: outputURL, as: .mp4)
            return outputURL
        } catch {
            logError(error)
            return nil
        }
    }
}
