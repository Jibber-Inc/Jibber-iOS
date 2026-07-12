//
//  PiPRecordingViewController+Output.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/4/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import AVFoundation
import Vision
import Combine

extension PiPRecordingViewController {
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        let isVideoOutput = output is AVCaptureVideoDataOutput
        let isFrontVideoOutput = connection.isVideoMirrored

        // If mirrored, then its the front camera output
        if isFrontVideoOutput, isVideoOutput {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            do {
                try self.sequenceHandler.perform([self.segmentationRequest],
                                                 on: imageBuffer,
                                                 orientation: .left)

                // Get the pixel buffer that contains the mask image.
                guard let maskPixelBuffer
                        = self.segmentationRequest.results?.first?.pixelBuffer else { return }
                self.frontCameraView.setImage(original: imageBuffer, mask: maskPixelBuffer)
            } catch {
                logError(error)
            }
        }

        // Keep the live segmentation preview active while idle, but do not
        // forward capture-pool buffers until the writers are ready.
        guard self.state == .recording else { return }
        
        // Create a one-owner sample wrapper for the iOS 27 consuming receiver API.
        // It is consumed synchronously below; no task retains capture-pool buffers.
        guard let recorderBuffer = try? CMSampleBuffer(copying: sampleBuffer) else { return }
        let recorderSample = SynchronousPiPRecorderSample(buffer: recorderBuffer)
        self.recorder.startRecording(sample: recorderSample,
                                     isVideoOutput: isVideoOutput,
                                     isFrontVideoOutput: isFrontVideoOutput,
                                     image: self.frontCameraView.currentCIImage)
    }
}
