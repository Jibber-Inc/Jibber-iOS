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

struct PiPRecording {
    var frontRecordingURL: URL?
    var backRecordingURL: URL?
    var previewURL: URL?
}

class PiPRecorder {
    
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
    
    let pixelBufferAttributes: [String: Any] = [ kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                                           kCVPixelBufferWidthKey: 480,
                                                          kCVPixelBufferHeightKey: 480,
                                              kCVPixelBufferMetalCompatibilityKey: true] as [String: Any]
    
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        
    var didCapturePIPRecording: ((PiPRecording) -> Void)?
    
    @Published private(set) var isReadyToRecord: Bool = false
    
    deinit {
        FileManager.clearTmpDirectory()
    }
    
    // MARK: - PUBLIC
    
    func initialize(backVideoSettings: [String: Any]?,
                    audioSettings: [String: Any]?,
                    on dispatchQue: DispatchQueue) {
        dispatchQue.async {
            self.reset()
            
            self.backVideoSettings = backVideoSettings
            self.audioSettings = audioSettings
            self.initializeFront()
            self.initializeBack()
            self.initializeAudio()
            
            self.isReadyToRecord = true
        }
    }
    
    // MARK: - RECORDING
    
    func recordFrontVideo(sampleBuffer: CMSampleBuffer, ciImage: CIImage?) {
        guard self.isReadyToRecord, let assetWriter = self.frontAssetWriter else { return }
        
        if assetWriter.status == .unknown {
            self.startWritingSession(with: assetWriter, and: sampleBuffer)
        } else if assetWriter.status == .writing {
            self.handleFrontInput(from: sampleBuffer, image: ciImage)
        }
    }
    
    func recordBackVideo(sampleBuffer: CMSampleBuffer) {
        guard self.isReadyToRecord, let assetWriter = self.backAssetWriter else { return }
        
        if assetWriter.status == .unknown {
            self.startWritingSession(with: assetWriter, and: sampleBuffer)
        } else if assetWriter.status == .writing {
            self.handleBackInput(from: sampleBuffer)
        }
    }
    
    func recordAudio(sampleBuffer: CMSampleBuffer) {
        guard self.isReadyToRecord, let assetWriter = self.frontAssetWriter else { return }
        
        if assetWriter.status == .unknown {
            self.startWritingSession(with: assetWriter, and: sampleBuffer)
        } else if assetWriter.status == .writing {
            self.handleAudioInput(from: sampleBuffer)
        }
    }
    
    // MARK: - STOP RECORDING
    
    private var stopRecordingTask: Task<Void, Error>?

    // This cant be called more than once per recording otherwise inputs will crash
    func stopRecording() async throws {
        // If we already have an initialization task, wait for it to finish.
        if let finishVideoTask = self.stopRecordingTask {
            try await finishVideoTask.value
            return
        }

        // Otherwise start a new initialization task and wait for it to finish.
        self.stopRecordingTask = Task {
            let frontURL = try await self.stopRecordingFront()
            let backURL = try await self.stopRecordingBack()
            let previewURL = await self.compressVideo(for: backURL)
            let recording = PiPRecording(frontRecordingURL: frontURL,
                                         backRecordingURL: backURL,
                                         previewURL: previewURL)
            self.didCapturePIPRecording?(recording)
        }

        do {
            try await self.stopRecordingTask?.value
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
        self.assetWriterAudioInput = nil
        self.isReadyToRecord = false
    }
    
    // MARK: - INITIALZE WRITERS/INPUTS
    
    private func initializeFront() {
        // Create an asset writer that records to a temporary file
        let outputFileName = NSUUID().uuidString + "front"
        let outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName).appendingPathExtension("mov")
        guard let assetWriter = try? AVAssetWriter(url: outputFileURL, fileType: .mov) else {
            return
        }
        
        // Add a video input
        let assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: self.frontVideoSettings)
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
        let outputFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName).appendingPathExtension("mov")
        guard let assetWriter = try? AVAssetWriter(url: outputFileURL, fileType: .mov), let settings = self.backVideoSettings else {
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
        guard let settings = self.audioSettings, let writer = self.frontAssetWriter, self.assetWriterAudioInput.isNil else { return }
        // Add an audio input
        let assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        assetWriterAudioInput.expectsMediaDataInRealTime = true
        if writer.canAdd(assetWriterAudioInput) {
            writer.add(assetWriterAudioInput)
        }
        
        self.assetWriterAudioInput = assetWriterAudioInput
    }
    
    private func startWritingSession(with writer: AVAssetWriter, and sampleBuffer: CMSampleBuffer) {
        writer.startWriting()
        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        writer.startSession(atSourceTime: startTime)
    }
    
    // MARK: - HANDLE SAMPLE BUFFERS
    
    private func handleFrontInput(from sampleBuffer: CMSampleBuffer, image: CIImage?) {
        guard let input = self.frontAssetWriterVideoInput,
                input.isReadyForMoreMediaData,
              let currentImage = image else { return }
        
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
    
    private func handleBackInput(from sampleBuffer: CMSampleBuffer) {
        guard let input = self.backAssetWriterVideoInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }
    
    private func handleAudioInput(from sampleBuffer: CMSampleBuffer) {
        guard let input = self.assetWriterAudioInput, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }
    
    // MARK: - STOP RECORDING 
    
    private func stopRecordingFront() async throws -> URL {
        guard let writer = self.frontAssetWriter else { throw ClientError.apiError(detail: "No front asset writer") }

        if writer.status == .writing {
            self.frontAssetWriterVideoInput?.markAsFinished()
            await writer.finishWriting()
            return writer.outputURL
        } else {
            throw ClientError.apiError(detail: "Front Failied \(writer.status)")
        }
    }
    
    private func stopRecordingBack() async throws -> URL {
        guard let writer = self.backAssetWriter else { throw ClientError.apiError(detail: "No front asset writer") }

        if writer.status == .writing {
            self.backAssetWriterVideoInput?.markAsFinished()
            await writer.finishWriting()
            return writer.outputURL
        } else {
            throw ClientError.apiError(detail: "Back Failied \(writer.status)")
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
