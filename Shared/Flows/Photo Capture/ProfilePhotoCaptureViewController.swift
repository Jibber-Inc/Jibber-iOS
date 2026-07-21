//
//  LoginProfilePhotoViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 8/12/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Coordinator
import ParseCore
import Lottie
import UIKit
import Combine
import AVFoundation
import Localization

enum PhotoState {
    case initial
    case cameraDenied
    case cameraRestricted
    case renderFaceImage
    case scanEyesOpen
    case captureEyesOpen
    case didCaptureEyesOpen
    case review
    case error
    case finish
}

class ProfilePhotoCaptureViewController: ViewController, Sizeable, Completable {

    typealias ResultType = Void

    var onDidComplete: ((Result<Void, Error>) -> Void)?
    var onRequestStateChanged: ((EventStatus) -> Void)?

    // MARK: - Views

    lazy var faceCaptureVC = FaceCaptureViewController()

    private let imageView = DisplayableImageView()
    private let button = ThemeButton()

    /// Canonical onboarding keeps Capture inside the camera content and submits
    /// the captured still with the conversation swipe gesture. Legacy callers
    /// continue to use this same button for both Capture and Use Photo.
    var usesEmbeddedComposer = false {
        didSet {
            self.faceCaptureVC.usesEmbeddedCaptureLayout = self.usesEmbeddedComposer
            guard self.isViewLoaded else { return }
            self.updatePrimaryButton(for: self.currentState)
            self.view.setNeedsLayout()
        }
    }

    /// Context presented by onboarding's shared typing-indicator view. The
    /// embedded camera label is hidden so guidance has a single visual home.
    @Published private(set) var contextText = ""

    var hasCapturedPhoto: Bool {
        self.currentState == .review && self.imageView.displayable?.image != nil
    }

    var canSubmitCapturedPhoto: Bool {
        self.hasCapturedPhoto && !self.isUploading
    }

    var primaryActionTitle: String {
        switch self.currentState {
        case .cameraDenied, .cameraRestricted:
            return self.openSettingsButtonTitle
        case .review:
            return self.reviewButtonTitle
        default:
            return self.captureButtonTitle
        }
    }

    var isPrimaryActionEnabled: Bool {
        switch self.currentState {
        case .cameraDenied, .cameraRestricted, .scanEyesOpen, .error, .review:
            return true
        case .initial, .renderFaceImage, .captureEyesOpen, .didCaptureEyesOpen, .finish:
            return false
        }
    }

#if DEBUG
    /// Deterministic screenshot fixture only. Production builds cannot enter this path.
    private let previewFixtureImageView = UIImageView()
    var usesLocalPreviewFixture = false
    private var isFaceCapturePreviewFixture: Bool {
        if self.usesLocalPreviewFixture { return true }
        let arguments = ProcessInfo.processInfo.arguments
        return (arguments.contains("-OnboardingPreview")
            || arguments.contains("OnboardingPreview"))
            && arguments.contains("faceCapture")
    }
#endif

    // MARK: - Configurable Copy

    var captureButtonTitle = "Capture" {
        didSet {
            guard self.isViewLoaded, self.currentState != .review else { return }
            self.updatePrimaryButton(for: self.currentState)
        }
    }

    var reviewButtonTitle = "Use this photo" {
        didSet {
            guard self.isViewLoaded, self.currentState == .review else { return }
            self.updatePrimaryButton(for: self.currentState)
        }
    }

    var noFaceMessage = "No face detected."
    var notSmilingMessage = "Don't forget to smile."
    var uploadErrorMessage = "There was an error uploading your photo."
    var scanningMessage = "Center your face"
    var cameraDeniedMessage = "Camera access is off. Open Settings to take your profile photo."
    var cameraRestrictedMessage = "Camera access is restricted on this device. Check Settings or contact your administrator."
    var cameraStartErrorMessage = "I couldn’t start the camera. Tap Capture to try again."
    var openSettingsButtonTitle = "Open Settings"

    // MARK: - Analytics

    override var analyticsIdentifier: String? {
        return "SCREEN_PHOTO"
    }

    // MARK: - State

    private var previousScanState: PhotoState = .scanEyesOpen
    @Published var currentState: PhotoState = .initial
    private var lastHandledFaceDetected: Bool?
    private var isUploading = false

    // MARK: - Life Cycle

    override func initializeViews() {
        super.initializeViews()

        self.addChild(viewController: self.faceCaptureVC)

        self.view.addSubview(self.imageView)
        self.imageView.alpha = 0.0

        self.view.addSubview(self.button)
        self.updatePrimaryButton(for: self.currentState)

        self.setupHandlers()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.currentState = .initial
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

#if DEBUG
        if self.isFaceCapturePreviewFixture {
            if self.currentState != .review {
                self.currentState = .scanEyesOpen
            }
            return
        }
#endif

        self.refreshCameraAuthorization()
    }

    private func refreshCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied:
            self.currentState = .cameraDenied
        case .restricted:
            self.currentState = .cameraRestricted
        case .authorized, .notDetermined:
            switch self.currentState {
            case .review, .finish:
                break
            default:
                self.currentState = .renderFaceImage
            }
        @unknown default:
            self.currentState = .cameraRestricted
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if self.faceCaptureVC.isSessionActive {
            self.faceCaptureVC.stopSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.button.setSize(with: self.view.width)
        self.button.centerOnX()
        self.button.pinToSafeAreaBottom()

        if self.usesEmbeddedComposer {
            let contentBottom = self.button.isHidden
                ? self.view.height
                : max(0, self.button.top - Theme.ContentOffset.short.value)
            self.faceCaptureVC.view.frame = CGRect(
                x: 0,
                y: 0,
                width: self.view.width,
                height: contentBottom
            )
            self.imageView.frame = self.faceCaptureVC.view.frame
        } else {
            self.faceCaptureVC.view.expandToSuperviewSize()
            self.imageView.expandToSuperviewSize()
        }

#if DEBUG
        if self.isFaceCapturePreviewFixture {
            self.installFaceCapturePreviewFixtureIfNeeded()
            self.previewFixtureImageView.expandToSuperviewSize()
        }
#endif
    }
    
    private func setupHandlers() {
        
        self.button.didSelect { [unowned self] in
            if self.usesEmbeddedComposer {
                self.didTapCaptureAction()
            } else {
                self.didTapPrimaryAction()
            }
        }
        self.button.accessibilityIdentifier = "onboarding.face.capture"
        self.setupImageAndCaptureHandlers()
    }

    /// Legacy entry point. Canonical onboarding calls the two explicit methods
    /// so Capture remains a tap while photo acceptance remains a swipe.
    func didTapPrimaryAction() {
#if DEBUG
        if self.isFaceCapturePreviewFixture {
            self.handleFaceCapturePreviewSelection()
            return
        }
#endif

        if self.currentState == .review {
            self.submitCapturedPhoto()
        } else {
            self.didTapCaptureAction()
        }
    }

    func didTapCaptureAction() {
#if DEBUG
        if self.isFaceCapturePreviewFixture {
            self.handleFaceCapturePreviewSelection()
            return
        }
#endif

        switch self.currentState {
        case .cameraDenied, .cameraRestricted:
            self.openCameraSettings()
        case .error where !self.faceCaptureVC.isSessionActive:
            self.currentState = .renderFaceImage
        case .scanEyesOpen, .error:
            guard self.faceCaptureVC.faceDetected else {
                self.animateError(with: self.noFaceMessage, show: true)
                return
            }
            self.currentState = .captureEyesOpen
        case .initial, .renderFaceImage, .captureEyesOpen, .didCaptureEyesOpen,
             .review, .finish:
            break
        }
    }

    func submitCapturedPhoto() {
        Task { _ = await self.submitCapturedPhotoAndWait() }
    }

    /// Holds both the local upload latch and the shared swipe transaction until
    /// persistence succeeds or fails. The captured still remains available on
    /// failure so a retry does not force a retake.
    @discardableResult
    func submitCapturedPhotoAndWait() async -> Bool {
        guard self.canSubmitCapturedPhoto,
              let image = self.imageView.displayable?.image else { return false }
        self.isUploading = true
        defer { self.isUploading = false }
        return await self.updateUser(with: image)
    }

    private func setupImageAndCaptureHandlers() {
        self.imageView.didSelect { [unowned self] in
            guard self.currentState == .review, !self.isUploading else { return }
            self.imageView.displayable = nil
            self.contextText = self.scanningMessage

#if DEBUG
            if self.isFaceCapturePreviewFixture {
                self.currentState = .scanEyesOpen
                return
            }
#endif

            self.currentState = .renderFaceImage
        }

        self.faceCaptureVC.$faceDetected
            .dropFirst()
            .mainSink { [weak self] faceDetected in
                guard let self else { return }

                switch self.currentState {
                case .renderFaceImage:
                    self.currentState = .scanEyesOpen
                case .scanEyesOpen, .error:
                    break
                default:
                    return
                }

                guard self.lastHandledFaceDetected != faceDetected else { return }
                self.lastHandledFaceDetected = faceDetected
                self.handleFace(isDetected: faceDetected)
            }.store(in: &self.cancellables)

        self.faceCaptureVC.didCapturePhoto = { [unowned self] image in
            switch self.currentState {
            case .captureEyesOpen:
                if self.faceCaptureVC.isSmiling {
                    self.currentState = .didCaptureEyesOpen
                    self.animateError(with: nil, show: false)
                    self.imageView.displayable = image
                    self.currentState = .review
                } else {
                    self.handleNotSmiling()
                }
            default:
                break
            }
        }

        self.faceCaptureVC.didResolveCameraAuthorization = { [weak self] status in
            self?.handleCameraAuthorization(status)
        }
        self.faceCaptureVC.didResolveSessionStart = { [weak self] didStart in
            guard let self,
                  !didStart,
                  self.viewIfLoaded?.window != nil else { return }
            self.currentState = .error
            self.contextText = self.cameraStartErrorMessage
            self.animateError(with: self.cameraStartErrorMessage, show: true)
        }

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .mainSink { [weak self] _ in
                guard let self, self.viewIfLoaded?.window != nil else { return }
                self.refreshCameraAuthorization()
            }.store(in: &self.cancellables)

        self.$currentState
            .mainSink { [weak self] state in
                guard let self else { return }
                self.handle(state: state)
            }.store(in: &self.cancellables)
    }

    private func updatePrimaryButton(for state: PhotoState) {
        let title: String
        switch state {
        case .cameraDenied, .cameraRestricted:
            title = self.openSettingsButtonTitle
        case .review:
            title = self.reviewButtonTitle
        default:
            title = self.captureButtonTitle
        }
        self.button.set(style: .custom(color: .D6, textColor: .white, text: title))
        self.button.accessibilityLabel = title
        self.button.isHidden = self.usesEmbeddedComposer
            && (state == .review || state == .finish)

#if DEBUG
        if self.isFaceCapturePreviewFixture, state != .finish {
            self.button.isEnabled = true
            self.button.isUserInteractionEnabled = true
            return
        }
#endif

        switch state {
        case .cameraDenied, .cameraRestricted, .scanEyesOpen, .error, .review:
            self.button.isEnabled = true
            self.button.isUserInteractionEnabled = true
        case .initial, .renderFaceImage, .captureEyesOpen, .didCaptureEyesOpen, .finish:
            self.button.isEnabled = false
        }
    }

    private func handle(state: PhotoState) {
        switch state {
        case .initial:
            self.contextText = self.scanningMessage
        case .cameraDenied:
            self.contextText = self.cameraDeniedMessage
            self.handleCameraUnavailable(message: self.cameraDeniedMessage)
        case .cameraRestricted:
            self.contextText = self.cameraRestrictedMessage
            self.handleCameraUnavailable(message: self.cameraRestrictedMessage)
        case .renderFaceImage:
            self.contextText = self.scanningMessage
            self.handleRenderImage()
        case .scanEyesOpen:
#if DEBUG
            if self.isFaceCapturePreviewFixture {
                // The local Product Design fixture already contains a centered
                // face. Keep its guidance representative without starting
                // AVFoundation or fabricating detector state.
                self.contextText = self.scanningMessage
                self.previousScanState = state
                break
            }
#endif
            self.contextText = self.faceCaptureVC.faceDetected
                ? self.scanningMessage
                : self.noFaceMessage
            self.previousScanState = state
            self.handleScanState()
        case .captureEyesOpen:
            self.handleCaptureState()
        case .error:
            if self.contextText.isEmpty {
                self.contextText = self.cameraStartErrorMessage
            }
        case .didCaptureEyesOpen:
            break
        case .review:
            self.contextText = self.reviewButtonTitle
            self.handleReviewState()
        case .finish:
            self.contextText = ""
            Task {
                await self.handleFinishState()
            }.add(to: self.autocancelTaskPool)
        }

        self.updatePrimaryButton(for: state)
        self.view.layoutNow()
    }

    private func handleFace(isDetected: Bool) {
        if isDetected {
            self.currentState = self.previousScanState
            self.contextText = self.scanningMessage
            self.faceCaptureVC.animate(text: "")
        } else {
            self.contextText = self.noFaceMessage
            self.faceCaptureVC.animate(text: self.noFaceMessage)
        }

        self.animateError(with: nil, show: !isDetected)

        UIView.animate(withDuration: 0.2, delay: 0.1, options: []) {
            self.faceCaptureVC.cameraView.alpha = isDetected ? 1.0 : 0.25
        }
    }

    private func handleNotSmiling() {
        self.contextText = self.notSmilingMessage
        self.animateError(with: self.notSmilingMessage, show: true)

        UIView.animate(withDuration: 0.2, delay: 0.1, options: []) {
            self.faceCaptureVC.cameraView.alpha = 0.5
        } completion: { completed in
            UIView.animate(withDuration: 0.2, delay: 0.0, options: []) {
                self.faceCaptureVC.cameraView.alpha = 1.0
            } completion: { _ in
                Task {
                    await Task.sleep(seconds: 2.0)
                    self.currentState = .scanEyesOpen
                    self.handleFace(isDetected: self.faceCaptureVC.faceDetected)
                }
            }
        }
    }
    
    private func handleRenderImage() {
#if DEBUG
        if self.isFaceCapturePreviewFixture {
            self.currentState = .scanEyesOpen
            return
        }
#endif

        self.lastHandledFaceDetected = nil
        self.faceCaptureVC.cameraView.alpha = 1
        self.faceCaptureVC.cameraViewContainer.layer.borderColor = ThemeColor.B1.color.cgColor
        self.faceCaptureVC.animate(text: self.scanningMessage)

        UIView.animate(withDuration: Theme.animationDurationStandard) {
            self.imageView.alpha = 0
            self.faceCaptureVC.animationView.alpha = 1
        } completion: { _ in
            self.faceCaptureVC.animationView.play()
        }

        self.faceCaptureVC.beginSession()
    }

    private func handleCameraAuthorization(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized:
            if self.currentState == .cameraDenied || self.currentState == .cameraRestricted {
                self.currentState = .renderFaceImage
            }
        case .denied:
            self.currentState = .cameraDenied
        case .restricted:
            self.currentState = .cameraRestricted
        case .notDetermined:
            break
        @unknown default:
            self.currentState = .cameraRestricted
        }
    }

    private func handleCameraUnavailable(message: String) {
        if self.faceCaptureVC.isSessionActive {
            self.faceCaptureVC.stopSession()
        }
        self.faceCaptureVC.animationView.stop()
        UIView.animate(withDuration: Theme.animationDurationStandard) {
            self.imageView.alpha = 0
            self.faceCaptureVC.animationView.alpha = 0
            self.faceCaptureVC.cameraView.alpha = 0.15
            self.faceCaptureVC.label.alpha = 1
            self.faceCaptureVC.cameraViewContainer.layer.borderColor = ThemeColor.red.color.cgColor
        }
        self.faceCaptureVC.animate(text: message)
    }

    private func openCameraSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsURL) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func handleScanState() {
        UIView.animate(withDuration: 0.2, animations: {
            self.imageView.alpha = 0
            self.faceCaptureVC.animationView.alpha = 0
            self.faceCaptureVC.label.alpha = 1.0
            self.view.layoutNow()
        })
    }

    private func handleCaptureState() {
        self.faceCaptureVC.capturePhoto()
    }
    
    private func handleReviewState() {
        if self.faceCaptureVC.isSessionActive {
            self.faceCaptureVC.stopSession()
        }

        UIView.animate(withDuration: Theme.animationDurationStandard) {
            self.imageView.alpha = 1.0
            self.faceCaptureVC.label.alpha = 0.0
            self.view.layoutNow()
        }
    }

    private func animateError(with message: String?, show: Bool) {
        if let message {
            self.faceCaptureVC.animate(text: message)
        }

        UIView.animate(withDuration: Theme.animationDurationStandard) {
            self.faceCaptureVC.cameraViewContainer.layer.borderColor = show
                ? ThemeColor.red.color.cgColor
                : ThemeColor.B1.color.cgColor
        }
    }

    @MainActor
    private func handleFinishState() async {
        self.cancellables.forEach { cancellable in
            cancellable.cancel()
        }

        self.complete(with: .success(()))
    }

    private func updateUser(with image: UIImage) async -> Bool {
#if DEBUG
        if self.isFaceCapturePreviewFixture {
            self.currentState = .finish
            return true
        }
#endif

        guard let currentUser = User.current(),
              let data = image.heicData else {
            return false
        }

        let nowString = Date.now.ISO8601Format().removeAllNonNumbers()

        let file = PFFileObject(name: "\(nowString).heic", data: data)
        currentUser.smallImage = file

        do {
            self.onRequestStateChanged?(.loading)
            await self.button.handleEvent(status: .loading)
            try await currentUser.saveToServer()
            await ToastScheduler.shared.schedule(
                toastType: .success(ImageSymbol.personCropCircle, "Profile picture updated")
            )
            await self.button.handleEvent(status: .complete)
            self.onRequestStateChanged?(.complete)

            self.currentState = .finish
            return true
        } catch {
            await self.button.handleEvent(status: .error(self.uploadErrorMessage))
            self.onRequestStateChanged?(.error(self.uploadErrorMessage))
            self.contextText = self.uploadErrorMessage
            self.animateError(with: self.uploadErrorMessage, show: true)
            return false
        }
    }

#if DEBUG
    /// Places the local fixture into the post-capture state without invoking
    /// AVFoundation or the upload/finalization path.
    func prepareCapturedPhotoPreview() {
        self.usesLocalPreviewFixture = true
        self.loadViewIfNeeded()
        guard let image = UIImage(named: "OnboardingFacePreview") else { return }
        self.imageView.displayable = image
        self.currentState = .review
        self.view.setNeedsLayout()
    }

    /// Installs a local, deterministic face image without starting AVFoundation.
    /// This exists only for `-OnboardingPreview faceCapture` visual captures.
    private func installFaceCapturePreviewFixtureIfNeeded() {
        if self.previewFixtureImageView.superview == nil {
            self.previewFixtureImageView.image = UIImage(named: "OnboardingFacePreview")
            self.previewFixtureImageView.contentMode = .scaleAspectFill
            self.previewFixtureImageView.clipsToBounds = true
            self.faceCaptureVC.cameraViewContainer.insertSubview(
                self.previewFixtureImageView,
                aboveSubview: self.faceCaptureVC.cameraView
            )
        }

        self.faceCaptureVC.animationView.alpha = 0
        self.faceCaptureVC.label.alpha = 0
    }

    /// Advances the visual fixture without invoking camera or Parse APIs.
    private func handleFaceCapturePreviewSelection() {
        switch self.currentState {
        case .review:
            // The screenshot fixture is intentionally local-only. Keep the
            // review state visible instead of firing onboarding completion,
            // which would otherwise enqueue canonical conversation sync.
            break
        case .initial, .cameraDenied, .cameraRestricted, .renderFaceImage, .scanEyesOpen, .error:
            guard let image = UIImage(named: "OnboardingFacePreview") else { return }
            self.imageView.displayable = image
            self.currentState = .review
        case .captureEyesOpen, .didCaptureEyesOpen, .finish:
            break
        }
    }
#endif
}
