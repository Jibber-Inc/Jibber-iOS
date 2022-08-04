//
//  PiPRecordingViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/3/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import AVFoundation

class PiPRecordingViewController: ViewController, AVCaptureVideoDataOutputSampleBufferDelegate  {
    
    lazy var session = AVCaptureMultiCamSession()
    lazy var recorder = PiPRecorder(frontVideoSettings: [:], backVideoSettings: [:])
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
        case multiCamNotSupported
    }
    
    private var setupResult: SessionSetupResult = .success
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    let dataOutputQueue = DispatchQueue(label: "data output queue")
    
    let backCameraVideoPreviewView = VideoPreviewView()
    let frontCameraVideoPreviewView = FrontPreviewVideoView()
    
    var backCameraDeviceInput: AVCaptureDeviceInput?
    let backCameraVideoDataOutput = AVCaptureVideoDataOutput()
    
    var frontCameraDeviceInput: AVCaptureDeviceInput?
    let frontCameraVideoDataOutput = AVCaptureVideoDataOutput()
    
    var isSessionRunning: Bool {
        return self.session.isRunning
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.addSubview(self.backCameraVideoPreviewView)
        self.view.addSubview(self.frontCameraVideoPreviewView)
        
        // Set up the back and front video preview views.
        self.backCameraVideoPreviewView.videoPreviewLayer.setSessionWithNoConnection(self.session)
        self.frontCameraVideoPreviewView.videoPreviewLayer.setSessionWithNoConnection(self.session)
        
        /*
        Configure the capture session.
        In general it is not safe to mutate an AVCaptureSession or any of its
        inputs, outputs, or connections from multiple threads at the same time.
        
        Don't do this on the main queue, because AVCaptureMultiCamSession.startRunning()
        is a blocking call, which can take a long time. Dispatch session setup
        to the sessionQueue so as not to block the main queue, which keeps the UI responsive.
        */
        self.sessionQueue.async {
            self.configureSession()
        }
    }
    
    // Must be called on the session queue
    private func configureSession() {
        guard self.setupResult == .success else { return }
        
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            print("MultiCam not supported on this device")
            self.setupResult = .multiCamNotSupported
            return
        }
        
        // When using AVCaptureMultiCamSession, it is best to manually add connections from AVCaptureInputs to AVCaptureOutputs
        self.session.beginConfiguration()
        
        defer {
            self.session.commitConfiguration()
            if self.setupResult == .success {
                self.checkSystemCost()
            }
        }
    
        guard self.configureBackCamera() else {
            self.setupResult = .configurationFailed
            return
        }
        
        guard self.configureFrontCamera() else {
            self.setupResult = .configurationFailed
            return
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        self.stopSession()
        super.viewWillDisappear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.backCameraVideoPreviewView.expandToSuperviewSize()
        
        self.frontCameraVideoPreviewView.squaredSize = self.view.width * 0.25
        self.frontCameraVideoPreviewView.pinToSafeAreaTop()
        self.frontCameraVideoPreviewView.pinToSafeAreaLeft()
    }
    
    // MARK: - PUBLIC
    
    func beginSession() {
        self.sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                //self.addObservers()
                self.session.startRunning()
                
            case .notAuthorized:
                break
            case .configurationFailed:
                break
            case .multiCamNotSupported:
                break
            }
        }
    }
    
    func stopSession() {
        self.sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
            }
        }
    }
    
    func startVideoCapture() {
       // self.recorder.startRecording(frontSampleBuffer: <#T##CMSampleBuffer#>, backSampleBuffer: <#T##CMSampleBuffer#>)
    }
    
    func stopVideoCapture() {
        self.recorder.stopRecording()
    }
    
    func beginPlayback() {
        guard let frontURL = self.recorder.recording?.frontRecordingURL,
                let backURL = self.recorder.recording?.backRecordingURL else { return }
        
        self.frontCameraVideoPreviewView.beginPlayback(with: frontURL)
        self.backCameraVideoPreviewView.beginPlayback(with: backURL)
    }
    
    func stopPlayback() {
        self.frontCameraVideoPreviewView.stopPlayback()
        self.backCameraVideoPreviewView.stopPlayback()
    }
}
