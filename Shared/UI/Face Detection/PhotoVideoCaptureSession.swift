//
//  LivePhotoViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/3/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import AVFoundation
import UIKit

@MainActor
final class PhotoVideoCaptureSession {

    weak var avCaptureDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    var didCapturePhoto: (@MainActor @Sendable () -> Void)?

    private enum State {
        case idle
        case authorizing
        case starting
        case running
        case stopping
    }

    var isRunning: Bool {
        self.state == .running
    }

    var isActive: Bool {
        self.state != .idle
    }

    var currentPosition: AVCaptureDevice.Position = .front
    var flashMode: AVCaptureDevice.FlashMode = .auto

    private let owner = CaptureSessionOwner()
    private var state: State = .idle
    private var authorizationTask: Task<Void, Never>?

    private lazy var photoCaptureDelegate = PhotoCaptureDelegateBridge { [weak self] in
        self?.didCapturePhoto?()
    }

    /// Requests camera access, then configures and starts the capture session on its serial queue.
    func begin() {
        guard self.state == .idle else { return }

        self.state = .authorizing
        self.authorizationTask = Task { [weak self] in
            let authorized = await AVCaptureDevice.requestAccess(for: .video)

            guard let self,
                  !Task.isCancelled,
                  self.state == .authorizing else { return }

            self.authorizationTask = nil

            guard authorized,
                  let avCaptureDelegate = self.avCaptureDelegate else {
                self.state = .idle
                return
            }

            self.state = .starting
            self.owner.start(position: self.currentPosition,
                             videoDelegate: VideoDelegateTransfer(avCaptureDelegate)) { [weak self] didStart in
                guard let self, self.state == .starting else { return }
                self.state = didStart ? .running : .idle
            }
        }
    }

    /// Stops the capture session and removes its inputs and outputs on the same serial queue.
    func stop() {
        self.authorizationTask?.cancel()
        self.authorizationTask = nil

        guard self.state != .idle else { return }

        self.state = .stopping
        self.owner.stop { [weak self] in
            guard let self, self.state == .stopping else { return }
            self.state = .idle
        }
    }

    // MARK: - Photo Capture

    /// Captures a photo of the current state of the capture output.
    func capturePhoto() {
        guard self.state == .running else { return }

        self.owner.capturePhoto(flashMode: self.flashMode,
                                delegate: self.photoCaptureDelegate)
    }
}

/// The only owner of `AVCaptureSession` and its mutable topology. The unchecked conformance is
/// justified by the invariant that every access is enqueued on `queue`.
private nonisolated final class CaptureSessionOwner: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.jibber.face-capture.session",
                                      qos: .userInitiated,
                                      autoreleaseFrequency: .workItem)
    private let dataOutputQueue = DispatchQueue(label: "com.jibber.face-capture.frames",
                                                qos: .userInitiated,
                                                autoreleaseFrequency: .workItem)
    private let session = AVCaptureSession()
    private var capturePhotoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?

    func start(position: AVCaptureDevice.Position,
               videoDelegate: VideoDelegateTransfer,
               completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.queue.async { [self] in
            dispatchPrecondition(condition: .onQueue(self.queue))

            guard !self.session.isRunning else {
                self.complete(true, using: completion)
                return
            }

            self.removeConfiguration()

            guard self.configure(position: position, videoDelegate: videoDelegate.value) else {
                self.removeConfiguration()
                self.complete(false, using: completion)
                return
            }

            self.session.startRunning()
            self.complete(self.session.isRunning, using: completion)
        }
    }

    func stop(completion: @escaping @MainActor @Sendable () -> Void) {
        self.queue.async { [self] in
            dispatchPrecondition(condition: .onQueue(self.queue))

            if self.session.isRunning {
                self.session.stopRunning()
            }

            self.removeConfiguration()

            Task { @MainActor in
                completion()
            }
        }
    }

    func capturePhoto(flashMode: AVCaptureDevice.FlashMode,
                      delegate: PhotoCaptureDelegateBridge) {
        self.queue.async { [self] in
            dispatchPrecondition(condition: .onQueue(self.queue))

            guard self.session.isRunning,
                  let capturePhotoOutput = self.capturePhotoOutput else { return }

            let photoSettings = AVCapturePhotoSettings()
            if #available(iOS 16.0, *) {
                photoSettings.maxPhotoDimensions = capturePhotoOutput.maxPhotoDimensions
            } else {
                photoSettings.isHighResolutionPhotoEnabled = true
            }
            photoSettings.flashMode = flashMode
            capturePhotoOutput.capturePhoto(with: photoSettings, delegate: delegate)
        }
    }

    private func configure(position: AVCaptureDevice.Position,
                           videoDelegate: AVCaptureVideoDataOutputSampleBufferDelegate) -> Bool {
        dispatchPrecondition(condition: .onQueue(self.queue))

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: position),
              let cameraInput = try? AVCaptureDeviceInput(device: camera) else {
            return false
        }

        self.session.beginConfiguration()
        defer { self.session.commitConfiguration() }

        guard self.session.canAddInput(cameraInput) else { return false }
        self.session.addInput(cameraInput)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                        kCVPixelFormatType_32BGRA]

        // The delegate is a nonisolated serial processor. It transfers only the resulting
        // immutable Core Image frame to the main-actor view controller.
        videoOutput.setSampleBufferDelegate(videoDelegate, queue: self.dataOutputQueue)

        guard self.session.canAddOutput(videoOutput) else { return false }
        self.session.addOutput(videoOutput)
        self.videoOutput = videoOutput

        if let videoConnection = videoOutput.connection(with: .video) {
            self.configurePortraitRotation(for: videoConnection)
        }

        let photoOutput = AVCapturePhotoOutput()
        guard self.session.canAddOutput(photoOutput) else { return false }
        self.session.addOutput(photoOutput)
        self.capturePhotoOutput = photoOutput

        if #available(iOS 16.0, *) {
            if let maxPhotoDimensions = camera.activeFormat.supportedMaxPhotoDimensions.max(by: {
                $0.width * $0.height < $1.width * $1.height
            }) {
                photoOutput.maxPhotoDimensions = maxPhotoDimensions
            }
        } else {
            photoOutput.isHighResolutionCaptureEnabled = true
        }

        if let photoConnection = photoOutput.connection(with: .video) {
            photoConnection.automaticallyAdjustsVideoMirroring = true
        }

        return true
    }

    private func removeConfiguration() {
        dispatchPrecondition(condition: .onQueue(self.queue))

        self.videoOutput?.setSampleBufferDelegate(nil, queue: nil)

        self.session.beginConfiguration()
        self.session.inputs.forEach(self.session.removeInput)
        self.session.outputs.forEach(self.session.removeOutput)
        self.session.commitConfiguration()

        self.capturePhotoOutput = nil
        self.videoOutput = nil
    }

    private func configurePortraitRotation(for connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(self.queue))

        if #available(iOS 17.0, *) {
            let portraitRotationAngle: CGFloat = 90
            guard connection.isVideoRotationAngleSupported(portraitRotationAngle) else { return }
            connection.videoRotationAngle = portraitRotationAngle
        } else {
            connection.videoOrientation = .portrait
        }
    }

    private func complete(_ didStart: Bool,
                          using completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        Task { @MainActor in
            completion(didStart)
        }
    }
}

private nonisolated struct VideoDelegateTransfer: @unchecked Sendable {
    let value: AVCaptureVideoDataOutputSampleBufferDelegate

    init(_ value: AVCaptureVideoDataOutputSampleBufferDelegate) {
        self.value = value
    }
}

/// AVFoundation chooses the photo callback thread. This bridge carries no media object across
/// executors; it only publishes completion back to the main actor.
private nonisolated final class PhotoCaptureDelegateBridge: NSObject,
                                                           AVCapturePhotoCaptureDelegate,
                                                           @unchecked Sendable {
    private let didFinishProcessing: @MainActor @Sendable () -> Void

    init(didFinishProcessing: @escaping @MainActor @Sendable () -> Void) {
        self.didFinishProcessing = didFinishProcessing
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let didFinishProcessing = self.didFinishProcessing
        Task { @MainActor in
            didFinishProcessing()
        }
    }
}
