//
//  LoginProfilePhotoViewController.swift
//  Benji
//
//  Created by Benji Dodgson on 8/12/19.
//  Copyright © 2019 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Parse
import TMROLocalization
import Lottie
import UIKit
import Combine
import AVFoundation

enum PhotoState {
    case initial
    case scanEyesOpen
    case scanEyesClosed
    case captureEyesOpen
    case captureEyesClosed
    case error(String)
    case finish
}

class PhotoViewController: ViewController, Sizeable, Completable {
    typealias ResultType = Void

    var onDidComplete: ((Result<Void, Error>) -> Void)?

    private lazy var cameraVC: FaceDetectionViewController = {
        let vc: FaceDetectionViewController = UIStoryboard(name: "FaceDetection", bundle: nil).instantiateViewController(withIdentifier: "FaceDetection") as! FaceDetectionViewController

        return vc
    }()

    private lazy var smilingDisclosureVC: FaceDisclosureViewController = {
        let vc = FaceDisclosureViewController(with: .smiling)
        vc.dismissHandlers.append { [unowned self] in
            self.currentState = .scanEyesClosed
        }
        vc.button.didSelect { [unowned self] in
            vc.dismiss(animated: true, completion: nil)
            self.currentState = .scanEyesClosed
        }
        return vc
    }()

    private lazy var focusDisclosureVC: FaceDisclosureViewController = {
        let vc = FaceDisclosureViewController(with: .eyesClosed)
        vc.dismissHandlers.append { [unowned self] in
            self.currentState = .finish
        }
        vc.button.didSelect { [unowned self] in
            vc.dismiss(animated: true, completion: nil)
            self.currentState = .finish
        }
        return vc
    }()

    private let animationView = AnimationView.with(animation: .faceScan)
    private var previousScanState: PhotoState = .scanEyesOpen

    @Published private(set) var currentState: PhotoState = .initial

    override func initializeViews() {
        super.initializeViews()

        self.animationView.loopMode = .loop

        self.view.addSubview(self.animationView)
        self.animationView.alpha = 0
        self.addChild(viewController: self.cameraVC)

        self.view.didSelect { [unowned self] in

            switch self.currentState {
            case .initial:
                self.currentState = .scanEyesOpen
            case .scanEyesOpen:
                guard self.cameraVC.faceDetected else { return }
                self.currentState = .captureEyesOpen
            case .scanEyesClosed:
                guard self.cameraVC.faceDetected else { return }
                self.currentState = .captureEyesClosed
            case .captureEyesOpen:
                break
            case .captureEyesClosed:
                break
            case .error:
                break
            case .finish:
                break
            }
        }

        self.cameraVC.didCapturePhoto = { [unowned self] image in
            switch self.currentState {
            case .captureEyesClosed:
                if self.cameraVC.eyesAreClosed {
                    Task {
                        await self.updateUser(with: image)
                    }
                } else {
                    self.handleEyesNotClosed()
                }
            case .captureEyesOpen:
                if self.cameraVC.isSmiling {
                    Task {
                        await self.updateUser(with: image)
                    }
                } else {
                    self.handleNotSmiling()
                }
            default:
                break
            }
        }

        self.$currentState
            .mainSink { [weak self] (state) in
                guard let `self` = self else { return }
                self.handle(state: state)
            }.store(in: &self.cancellables)

        self.cameraVC.$faceDetected
            .removeDuplicates()
            .mainSink(receiveValue: { [unowned self] (faceDetected) in
                switch self.currentState {
                case .scanEyesOpen, .scanEyesClosed, .error(_):
                    self.handleFace(isDetected: faceDetected)
                default:
                    break
                }
            }).store(in: &self.cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.currentState = .initial
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.animationView.size = CGSize(width: 140, height: 140)
        self.animationView.centerOnXAndY()

        self.cameraVC.view.expandToSuperviewSize()
    }

    private func handle(state: PhotoState) {
        switch state {
        case .initial:
            delay(0.5) {
                self.handleInitialState()
            }
        case .scanEyesOpen, .scanEyesClosed:
            self.previousScanState = state
            self.handleScanState()
        case .captureEyesOpen, .captureEyesClosed:
            self.handleCaptureState()
        case .error:
            self.handleErrorState()
        case .finish:
            Task {
                await self.handleFinishState()
            }
        }

        self.view.layoutNow()
    }

    private func handleInitialState() {

        if self.animationView.alpha == 0 {
            UIView.animate(withDuration: Theme.animationDuration, animations: {
                self.animationView.alpha = 1
            }) { (completed) in
                self.animationView.play()
            }
        } else {
            delay(Theme.animationDuration) {
                self.animationView.play()
            }
        }
    }

    private func handleFace(isDetected: Bool) {

        if isDetected {
            self.currentState = self.previousScanState
        } else {
            self.currentState = .error("Please show your face.")
        }

        UIView.animate(withDuration: 0.2, delay: 0.1, options: []) {
            self.cameraVC.previewLayer.opacity = isDetected ? 1.0 : 0.25
        } completion: { completed in

        }
    }

    private func handleNotSmiling() {
        self.currentState = .error("Please smile! 😀")

        UIView.animate(withDuration: 0.2, delay: 0.1, options: []) {
            self.cameraVC.previewLayer.opacity = 0.5
        } completion: { completed in
            UIView.animate(withDuration: 0.2, delay: 0.0, options: []) {
                self.cameraVC.previewLayer.opacity = 1.0
            } completion: { _ in
                Task {
                    await Task.sleep(seconds: 1.5)
                    self.currentState = .scanEyesOpen
                }
            }
        }
    }

    private func handleEyesNotClosed() {
        self.currentState = .error("Please close your eyes")

        UIView.animate(withDuration: 0.2, delay: 0.1, options: []) {
            self.cameraVC.previewLayer.opacity = 0.5
        } completion: { completed in
            UIView.animate(withDuration: 0.2, delay: 1.5, options: []) {
                self.cameraVC.previewLayer.opacity = 1.0
            } completion: { _ in
                self.currentState = .scanEyesClosed
            }
        }
    }

    private func handleScanState() {
        if !self.cameraVC.session.isRunning {
            self.cameraVC.begin()
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.animationView.alpha = 0
        }) { (completed) in

        }
    }

    private func handleCaptureState() {
        self.cameraVC.capturePhoto()
    }

    private func handleErrorState() {
        self.complete(with: .failure(ClientError.message(detail: "There was a problem. Please try again.")))
    }

    @MainActor
    private func handleFinishState() async {
        self.cancellables.forEach { (cancellable) in
            cancellable.cancel()
        }

        self.complete(with: .success(()))
    }

    private func updateUser(with image: UIImage) async {
        guard let currentUser = User.current(), let data = image.previewData else { return }

        switch self.currentState {
        case .captureEyesOpen:
            let file = PFFileObject(name:"small_image.jpeg", data: data)
            currentUser.smallImage = file
        case .captureEyesClosed:
            let file = PFFileObject(name:"focus_image.jpeg", data: data)
            currentUser.focusImage = file
        default:
            break
        }

        do {
            try await currentUser.saveToServer()

            switch self.currentState {
            case .captureEyesOpen:
                self.present(self.smilingDisclosureVC, animated: true, completion: nil)
                //self.currentState = .scanEyesClosed
            case .captureEyesClosed:
                self.present(self.focusDisclosureVC, animated: true, completion: nil)
                //self.currentState = .finish
            default:
                break
            }
        } catch {
            self.currentState = .error("There was an error uploading your photo.")
        }
    }
}
