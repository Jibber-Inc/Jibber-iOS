//
//  PiPRecordingViewController+Cameras.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/3/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import AVFoundation

extension PiPRecordingViewController {
    
    func configureBackCamera() -> Bool {
        // Find the back camera
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            logDebug("Could not find the back camera")
            return false
        }
        
        // Add the back camera input to the session
        do {
            self.backInput = try AVCaptureDeviceInput(device: backCamera)
            
            guard let backCameraDeviceInput = self.backInput,
                  self.session.canAddInput(backCameraDeviceInput) else {
                logDebug("Could not add back camera device input")
                    return false
            }
            self.session.addInputWithNoConnections(backCameraDeviceInput)
        } catch {
            print("Could not create back camera device input: \(error)")
            return false
        }
        
        // Find the back camera device input's video port
        guard let backCameraDeviceInput = self.backInput,
            let backCameraVideoPort = backCameraDeviceInput.ports(for: .video,
                                                              sourceDeviceType: backCamera.deviceType,
                                                              sourceDevicePosition: backCamera.position).first else {
            logDebug("Could not find the back camera device input's video port")
                                                                return false
        }
        
        // Add the back camera video data output
        guard self.session.canAddOutput(self.backOutput) else {
            logDebug("Could not add the back camera video data output")
            return false
        }
        self.session.addOutputWithNoConnections(self.backOutput)
        // Check if CVPixelFormat Lossy or Lossless Compression is supported
        
        if self.backOutput.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_Lossy_32BGRA) {
            // Set the Lossy format
            logDebug("Selecting lossy pixel format")
            self.backOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_Lossy_32BGRA)]
        } else if self.backOutput.availableVideoPixelFormatTypes.contains(kCVPixelFormatType_Lossless_32BGRA) {
            // Set the Lossless format
            logDebug("Selecting a lossless pixel format")
            self.backOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_Lossless_32BGRA)]
        } else {
            // Set to the fallback format
            logDebug("Selecting a 32BGRA pixel format")
            self.backOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        }
        
        self.backOutput.setSampleBufferDelegate(self, queue: .main)
                
        // Connect the back camera device input to the back camera video data output
        let backCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [backCameraVideoPort],
                                                                      output: self.backOutput)
        
        guard self.session.canAddConnection(backCameraVideoDataOutputConnection) else {
            logDebug("Could not add a connection to the back camera video data output")
            return false
        }
        self.session.addConnection(backCameraVideoDataOutputConnection)
        self.configurePortraitRotation(for: backCameraVideoDataOutputConnection)

        // Connect the back camera input to the preview in the same topology transaction.
        let backCameraVideoPreviewLayerConnection = AVCaptureConnection(inputPort: backCameraVideoPort,
                                                                        videoPreviewLayer: self.backCameraView.videoPreviewLayer)
        guard self.session.canAddConnection(backCameraVideoPreviewLayerConnection) else {
            logDebug("Could not add a connection to the back camera video preview layer")
            return false
        }
        self.session.addConnection(backCameraVideoPreviewLayerConnection)
        
        return true
    }
    
    func configureFrontCamera() -> Bool {
        // Find the front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            logDebug("Could not find the front camera")
            return false
        }
        
        // Add the front camera input to the session
        do {
            self.frontInput = try AVCaptureDeviceInput(device: frontCamera)
            
            guard let frontCameraDeviceInput = self.frontInput,
                  self.session.canAddInput(frontCameraDeviceInput) else {
                logDebug("Could not add front camera device input")
                    return false
            }
            self.session.addInputWithNoConnections(frontCameraDeviceInput)
        } catch {
            logDebug("Could not create front camera device input: \(error)")
            return false
        }
        
        // Find the front camera device input's video port
        guard let frontCameraDeviceInput = self.frontInput,
            let frontCameraVideoPort = frontCameraDeviceInput.ports(for: .video,
                                                                    sourceDeviceType: frontCamera.deviceType,
                                                                    sourceDevicePosition: frontCamera.position).first else {
            logDebug("Could not find the front camera device input's video port")
                                                                        return false
        }
        
        // Add the front camera video data output
        guard self.session.canAddOutput(self.frontOutput) else {
            logDebug("Could not add the front camera video data output")
            return false
        }
        self.session.addOutputWithNoConnections(self.frontOutput)
        // Check if CVPixelFormat Lossy or Lossless Compression is supported
        
        self.frontOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        self.frontOutput.setSampleBufferDelegate(self, queue: .main)
        
        // Connect the front camera device input to the front camera video data output
        let frontCameraVideoDataOutputConnection = AVCaptureConnection(inputPorts: [frontCameraVideoPort],
                                                                       output: self.frontOutput)
        guard self.session.canAddConnection(frontCameraVideoDataOutputConnection) else {
            logDebug("Could not add a connection to the front camera video data output")
            return false
        }
        
        self.configurePortraitRotation(for: frontCameraVideoDataOutputConnection)
        frontCameraVideoDataOutputConnection.automaticallyAdjustsVideoMirroring = false
        frontCameraVideoDataOutputConnection.isVideoMirrored = true
        
        self.session.addConnection(frontCameraVideoDataOutputConnection)
        
        return true
    }
    
    func configureMicrophone() -> Bool {
        // Find the microphone
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            logDebug("Could not find the microphone")
            return false
        }
        
        // Add the microphone input to the session
        do {
            self.micInput = try AVCaptureDeviceInput(device: microphone)
            
            guard let microphoneDeviceInput = self.micInput,
                  self.session.canAddInput(microphoneDeviceInput) else {
                logDebug("Could not add microphone device input")
                    return false
            }
            self.session.addInputWithNoConnections(microphoneDeviceInput)
        } catch {
            logDebug("Could not create microphone input: \(error)")
            return false
        }
        
        // Find the audio device input's front audio port
        guard let frontMicrophonePort = self.micInput?.ports(for: .audio,
                                                             sourceDeviceType: microphone.deviceType,
                                                             sourceDevicePosition: .front).first else {
            logDebug("Could not find the front camera device input's audio port")
            return false
        }
        
        // Add the front microphone audio data output
        guard self.session.canAddOutput(self.micDataOutput) else {
            logDebug("Could not add the front microphone audio data output")
            return false
        }
        self.session.addOutputWithNoConnections(self.micDataOutput)
        self.micDataOutput.setSampleBufferDelegate(self, queue: .main)
        
        // Connect the front microphone to the back audio data output
        let frontMicrophoneAudioDataOutputConnection = AVCaptureConnection(inputPorts: [frontMicrophonePort], output: self.micDataOutput)
        guard self.session.canAddConnection(frontMicrophoneAudioDataOutputConnection) else {
            logDebug("Could not add a connection to the front microphone audio data output")
            return false
        }
        self.session.addConnection(frontMicrophoneAudioDataOutputConnection)
        
        return true
    }

    private func configurePortraitRotation(for connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            let portraitRotationAngle: CGFloat = 90
            guard connection.isVideoRotationAngleSupported(portraitRotationAngle) else { return }
            connection.videoRotationAngle = portraitRotationAngle
        } else {
            connection.videoOrientation = .portrait
        }
    }
}
