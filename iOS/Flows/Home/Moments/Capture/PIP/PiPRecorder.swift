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

actor PiPRecorder {
    
    private var frontAssetWriter: AVAssetWriter?
    private var frontAssetWriterVideoInput: AVAssetWriterInput?
    
    private var backAssetWriter: AVAssetWriter?
    private var backAssetWriterVideoInput: AVAssetWriterInput?
    
    private var assetWriterAudioInput: AVAssetWriterInput?
    
    private let frontVideoSettings: [String: Any] = [AVVideoCodecKey : AVVideoCodecType.hevcWithAlpha,
                                                     AVVideoWidthKey : 480,
                                                    AVVideoHeightKey : 480,
                                     AVVideoCompressionPropertiesKey : [AVVideoQualityKey : 0.5,
                                          kVTCompressionPropertyKey_TargetQualityForAlpha : 0.5]]
    
    private var backVideoSettings: [String: Any]?
    private var audioSettings: [String: Any]?
    
    let pixelBufferAttributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                                          kCVPixelBufferWidthKey: 480,
                                                         kCVPixelBufferHeightKey: 480,
                                             kCVPixelBufferMetalCompatibilityKey: true] as [String: Any]
    
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
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
    
    func initialize(backVideoSettings: [String: Any]?, audioSettings: [String: Any]?) {
        self.reset()
        
        self.backVideoSettings = backVideoSettings
        self.audioSettings = audioSettings
        self.initializeFront()
        self.initializeBack()
        self.initializeAudio()
        
        self.isReadyToRecord = true
    }
    
    // MARK: - RECORDING
    
    func startRecording(with sampleBuffer: CMSampleBuffer,
                        isVideoOutput: Bool,
                        isFrontVideoOutput: Bool, 
                        ciImage: CIImage?) {
        guard self.isReadyToRecord else { return }
        
        if isVideoOutput {
            if isFrontVideoOutput {
                self.recordFrontVideo(sampleBuffer: sampleBuffer, ciImage: ciImage)
            } else {
                self.recordBackVideo(sampleBuffer: sampleBuffer)
            }
        } else {
            self.recordAudio(sampleBuffer: sampleBuffer)
        }
    }
    
    private func recordFrontVideo(sampleBuffer: CMSampleBuffer, ciImage: CIImage?) {
        guard self.isReadyToRecord, let assetWriter = self.frontAssetWriter else { return }
        
        if assetWriter.status == .unknown {
            self.startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            self.startWritingSession(with: assetWriter, startTime: self.startTime!)
            self.handleFrontInput(from: sampleBuffer, image: ciImage)
        } else if assetWriter.status == .writing {
            self.handleFrontInput(from: sampleBuffer, image: ciImage)
        }
    }
    
    private func recordBackVideo(sampleBuffer: CMSampleBuffer) {
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
    
    private func recordAudio(sampleBuffer: CMSampleBuffer) {
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
        self.frontAssetWriterVideoInput = nil
        self.backAssetWriter = nil
        self.backAssetWriterVideoInput = nil
        self.assetWriterAudioInput = nil
        self.pixelBufferAdaptor = nil
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
        assetWriterVideoInput.expectsMediaDataInRealTime = true
        assetWriterVideoInput.mediaTimeScale = CMTimeScale(bitPattern: 600)
        if assetWriter.canAdd(assetWriterVideoInput) {
            assetWriter.add(assetWriterVideoInput)
        }
        
        self.frontAssetWriter = assetWriter
        self.frontAssetWriterVideoInput = assetWriterVideoInput
        
        self.pixelBufferAdaptor
        = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput,
                                               sourcePixelBufferAttributes: self.pixelBufferAttributes)
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
        assetWriterVideoInput.expectsMediaDataInRealTime = true
        if assetWriter.canAdd(assetWriterVideoInput) {
            assetWriter.add(assetWriterVideoInput)
        }
        
        self.backAssetWriter = assetWriter
        self.backAssetWriterVideoInput = assetWriterVideoInput
    }
    
    private func initializeAudio() {
        guard let settings = self.audioSettings,
              let frontAssetWriter = self.frontAssetWriter,
              self.assetWriterAudioInput.isNil else {
            return
        }

        // Add an audio input
        let assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        assetWriterAudioInput.expectsMediaDataInRealTime = true
        if frontAssetWriter.canAdd(assetWriterAudioInput) {
            frontAssetWriter.add(assetWriterAudioInput)
        }

        self.assetWriterAudioInput = assetWriterAudioInput
    }
    
    private func startWritingSession(with writer: AVAssetWriter,
                                     startTime: CMTime) {
        writer.startWriting()
        writer.startSession(atSourceTime: startTime)
    }
    
    // MARK: - HANDLE SAMPLE BUFFERS
    
    private func handleFrontInput(from sampleBuffer: CMSampleBuffer, image: CIImage?) {
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let input = self.frontAssetWriterVideoInput,
              input.isReadyForMoreMediaData,
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

        if self.pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: currentTime) == true {
            self.lastFrontVideoTime = currentTime
            self.hasWrittenFirstFrontVideoFrame = true
        }
    }
    
    private func handleBackInput(from sampleBuffer: CMSampleBuffer) {
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let input = self.backAssetWriterVideoInput,
              input.isReadyForMoreMediaData,
              self.hasWrittenFirstFrontVideoFrame,
              self.shouldAppend(currentTime, after: self.lastBackVideoTime) else { return }
        if input.append(sampleBuffer) {
            self.lastBackVideoTime = currentTime
        }
    }
    
    private func handleAudioInput(from sampleBuffer: CMSampleBuffer) {
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard let input = self.assetWriterAudioInput,
              input.isReadyForMoreMediaData,
              self.hasWrittenFirstFrontVideoFrame,
              self.shouldAppend(currentTime, after: self.lastAudioTime) else { return }
        if input.append(sampleBuffer) {
            self.lastAudioTime = currentTime
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
            self.frontAssetWriterVideoInput?.markAsFinished()
            self.assetWriterAudioInput?.markAsFinished()
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
            self.backAssetWriterVideoInput?.markAsFinished()
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
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName).appendingPathExtension("mov")
        
        guard let exportSession = AVAssetExportSession(asset: urlAsset,
                                                       presetName: AVAssetExportPresetLowQuality) else {
            return nil
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        await exportSession.export()
        return outputURL
    }
}
