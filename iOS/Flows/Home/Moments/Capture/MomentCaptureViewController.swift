//
//  MomentCaptureViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/3/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Parse
import Localization
import Speech
import KeyboardManager

 class MomentCaptureViewController: PiPRecordingViewController {

     override var analyticsIdentifier: String? {
         return "SCREEN_MOMENT"
     }

     private let label = ThemeLabel(font: .medium, textColor: .white)
     private let doneButton = ThemeButton()
     private let textView = CaptionTextView()

     var didCompleteMoment: ((Moment) -> Void)? = nil

     static let maxDuration: TimeInterval = 6.0
     let cornerRadius: CGFloat = 30

     override func initializeViews() {
         super.initializeViews()
         
         self.modalPresentationStyle = .popover
         if let pop = self.popoverPresentationController {
             let sheet = pop.adaptiveSheetPresentationController
             sheet.detents = [.large()]
             sheet.prefersGrabberVisible = true
             sheet.prefersScrollingExpandsWhenScrolledToEdge = true
             sheet.preferredCornerRadius = self.cornerRadius
         }
         
         self.view.set(backgroundColor: .B0)

         self.presentationController?.delegate = self

         self.backCameraView.layer.cornerRadius = self.cornerRadius

         self.view.addSubview(self.label)
         self.label.showShadow(withOffset: 0, opacity: 1.0)

         self.view.addSubview(self.doneButton)
         self.doneButton.set(style: .custom(color: .white, textColor: .B0, text: "Done"))
         
         self.view.addSubview(self.textView)
         self.textView.textAlignment = .center
         
         self.setupHandlers()
     }

     override func viewDidLayoutSubviews() {
         super.viewDidLayoutSubviews()
                  
         self.label.setSize(withWidth: Theme.getPaddedWidth(with: self.view.width))
         self.label.centerOnX()
         
         self.doneButton.setSize(with: self.view.width)
         self.doneButton.centerOnX()

         if self.state == .playback, !self.isBeingClosed {
             self.doneButton.pinToSafeAreaBottom()
             self.label.match(.bottom, to: .top, of: self.doneButton, offset: .negative(.long))
         } else {
             self.doneButton.top = self.view.height
             self.label.pinToSafeAreaBottom()
         }
         
         self.textView.setSize(withMaxWidth: self.doneButton.width)
         self.textView.match(.left, to: .left, of: self.doneButton)
         
         if KeyboardManager.shared.isKeyboardShowing {
             self.textView.bottom = self.view.height - KeyboardManager.shared.cachedKeyboardEndFrame.height - Theme.ContentOffset.long.value
         } else {
             self.textView.match(.bottom, to: .top, of: self.doneButton, offset: .negative(.long))
         }
     }

     private func setupHandlers() {
         
         self.frontCameraView.animationDidEnd = { [unowned self] in
             guard self.state == .recording else { return }
             self.stopRecording()
         }

         self.view.didSelect { [unowned self] in
             if self.textView.isFirstResponder {
                 self.textView.resignFirstResponder()
             } else if self.state == .playback {
                 self.state = .idle
             }
         }

         self.doneButton.didSelect { [unowned self] in
             Task {
                 guard let recording = self.recording,
                       let moment = await self.createMoment(from: recording) else { return }
                 self.didCompleteMoment?(moment)
             }
         }
         
         KeyboardManager.shared.$currentEvent.mainSink { [unowned self] event in
             UIView.animate(withDuration: Theme.animationDurationFast) {
                 self.view.layoutNow()
                 self.textView.backgroundColor = KeyboardManager.shared.isKeyboardShowing ? ThemeColor.B0.color.withAlphaComponent(0.8) : ThemeColor.B0.color.withAlphaComponent(0.4)
             }
         }.store(in: &self.cancellables)
     }

     override func handle(state: State) {
         super.handle(state: state)
         
         switch state {
         case .idle:
             self.textView.alpha = 0 
             self.animate(text: "Press and Hold")
         case .playback, .recording:
             self.animate(text: "")
         case .error:
             self.animate(text: "Recording Failed")
         }
     }
     
     override func handleSpeech(result: SFSpeechRecognitionResult?) {
         self.textView.animateSpeech(result: result)
         self.view.layoutNow()
     }

     private func createMoment(from recording: PiPRecording) async -> Moment? {
         await self.doneButton.handleEvent(status: .loading)
         
         do {
             return  try await MomentsStore.shared.createMoment(from: recording,
                                                                caption: self.textView.text)
         } catch {
             await self.doneButton.handleEvent(status: .error("Error"))
             return nil
         }
     }
     
     private var animateTask: Task<Void, Never>?
     
     func animate(text: Localized) {
         self.animateTask?.cancel()
         
         self.animateTask = Task { [weak self] in
             guard let `self` = self else { return }
             
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

     override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
         super.touchesBegan(touches, with: event)
         guard self.state == .idle else { return }

         self.startRecording()
     }

     override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
         super.touchesEnded(touches, with: event)
         guard self.state == .recording else { return }
         
         self.stopRecording()
     }

     override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
         super.touchesCancelled(touches, with: event)
         guard self.state == .recording else { return }
         
         self.stopRecording()
     }
 }

 extension MomentCaptureViewController: UIAdaptivePresentationControllerDelegate {

     func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
         self.frontCameraView.stopRecordingAnimation()
         return true
     }
 }
