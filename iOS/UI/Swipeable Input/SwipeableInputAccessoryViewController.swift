//
//  SwipeableInputAccessoryViewController.swift
//  Jibber
//
//  Created by Martin Young on 3/8/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Lottie
import Combine

protocol SwipeableInputAccessoryViewControllerDelegate: AnyObject {
    /// The accessory has begun a swipe interaction.
    func swipeableInputAccessoryDidBeginSwipe(_ controller: SwipeableInputAccessoryViewController)
    /// The accessory view updated the position of the sendable's preview view's position.
    func swipeableInputAccessory(_ controller: SwipeableInputAccessoryViewController,
                                 didUpdatePreviewFrame frame: CGRect,
                                 for sendable: Sendable)
    /// The accessory view wants to send the sendable with the preview with the specified frame.
    /// The delegate should return true if the sendable was sent.
    func swipeableInputAccessory(_ controller: SwipeableInputAccessoryViewController,
                                 triggeredSendFor sendable: Sendable,
                                 withPreviewFrame frame: CGRect) -> Bool
    /// The accessory view finished its swipe interaction.
    func swipeableInputAccessory(_ controller: SwipeableInputAccessoryViewController,
                                 didFinishSwipeSendingSendable didSend: Bool)

    /// The avatar view in the accessory was tapped.
    func swipeableInputAccessoryDidTapAvatar(_ controller: SwipeableInputAccessoryViewController)
}


class SwipeableInputAccessoryViewController: ViewController {

    enum InputState {
        /// The input field is fit to the current input. Swipe to send is enabled.
        case collapsed
        /// The input field is expanded and can be tapped to edit/copy/paste. Swipe to send is disabled.
        case expanded
    }

    weak var delegate: SwipeableInputAccessoryViewControllerDelegate?

    // MARK: - Drag and Drop Properties

    /// The rough area that we need to drag and drop messages to send them.
    var dropZoneFrame: CGRect = .zero

    // MARK:  - Views

    lazy var swipeInputView: SwipeableInputAccessoryView = SwipeableInputAccessoryView.fromNib()
    private lazy var panGestureHandler = SwipeInputPanGestureHandler(viewController: self)

    /// The current input state of the accessory view.
    @Published var inputState: InputState = .collapsed

    // MARK: - Message State

    var currentContext: MessageContext = .respectful {
        didSet {
            self.swipeInputView.deliveryTypeView.configure(for: self.currentContext)
        }
    }

    var currentEmotion: Emotion?

    var editableMessage: Messageable?
    var currentMessageKind: MessageKind = .text(String())
    var sendable: SendableObject?

    // MARK: - Layout/Animation Properties

    private lazy var hintAnimator = SwipeInputHintAnimator(swipeInputView: self.swipeInputView)

    // MARK: BaseView Setup and Layout

    override func loadView() {
        self.view = self.swipeInputView
    }

    override func initializeViews() {
        super.initializeViews()

        self.swipeInputView.emotionView.didSelectEmotion = { [unowned self] emotion in
            AnalyticsManager.shared.trackEvent(type: .emotionSelected, properties: ["value": emotion.rawValue])
            self.currentEmotion = emotion
        }

        self.swipeInputView.deliveryTypeView.didSelectContext = { [unowned self] context in
            AnalyticsManager.shared.trackEvent(type: .deliveryTypeSelected, properties: ["value": context.rawValue])
            self.currentContext = context
        }

        self.swipeInputView.avatarView.didSelect { [unowned self] in
            self.delegate?.swipeableInputAccessoryDidTapAvatar(self)
        }

        self.setupGestures()
        self.setupHandlers()
    }

    func resetDeliveryType() {
        self.currentContext = .respectful
        self.swipeInputView.deliveryTypeView.reset()
    }

    private lazy var panRecognizer
    = SwipeGestureRecognizer { [unowned self] (recognizer) in
        self.panGestureHandler.handle(pan: recognizer)
    }
    private lazy var inputFieldTapRecognizer = TapGestureRecognizer(taps: 1) { [unowned self] recognizer in
        self.handleInputTap()
    }
    private lazy var backgroundTapRecognizer = TapGestureRecognizer { [unowned self] recognizer in
        self.handleBackgroundTap()
    }

    func setupGestures() {
        self.panRecognizer.touchesDidBegin = { [unowned self] in
            // Stop playing animations when the user interacts with the view.
            self.hintAnimator.updateSwipeHint(shouldPlay: false)
        }
        self.swipeInputView.gestureButton.addGestureRecognizer(self.panRecognizer)

        self.swipeInputView.gestureButton.addGestureRecognizer(self.inputFieldTapRecognizer)

        self.swipeInputView.collapseButton.didSelect { [unowned self] in
            self.inputState = .collapsed
        }

        self.swipeInputView.addGestureRecognizer(self.backgroundTapRecognizer)
    }

    private func handleInputTap() {
        if self.swipeInputView.textView.isFirstResponder {
            // When the text view is editing, double taps should expand it.
            self.inputState = .expanded
        } else {
            // If we're not editing, a tap starts editing.
            self.swipeInputView.textView.updateInputView(type: .keyboard, becomeFirstResponder: true)
        }
    }

    private func handleBackgroundTap() {
        if self.inputState == .expanded {
            self.inputState = .collapsed
        } else if self.swipeInputView.textView.isFirstResponder {
            self.swipeInputView.textView.resignFirstResponder()
        }
    }

    private func setupHandlers() {
        self.updateInputType(with: .keyboard)

        KeyboardManager.shared
            .$currentEvent
            .mainSink { [unowned self] currentEvent in
                switch currentEvent {
                case .willShow:
                    self.showDetail(shouldShow: true)
                    self.hintAnimator.updateSwipeHint(shouldPlay: false)
                case .willHide:
                    self.showDetail(shouldShow: false)
                    self.hintAnimator.updateSwipeHint(shouldPlay: false)
                case .didHide:
                    self.swipeInputView.textView.updateInputView(type: .keyboard, becomeFirstResponder: false)
                    self.inputState = .collapsed
                default:
                    break
                }
            }.store(in: &self.cancellables)

        self.swipeInputView.textView.$inputText.mainSink { [unowned self] text in
            self.handleTextChange(text)
            self.updateInputState(with: self.swipeInputView.textView.numberOfLines)
            self.swipeInputView.countView.update(with: text.count,
                                                 max: self.swipeInputView.textView.maxLength)
        }.store(in: &self.cancellables)

        self.swipeInputView.textView.$isEditing.mainSink { [unowned self] isEditing in
            // If we are editing, a double tap should trigger the expanded state.
            // If we're not editing, it takes 1 tap to start.
            self.inputFieldTapRecognizer.numberOfTapsRequired = isEditing ? 2 : 1
        }.store(in: &self.cancellables)

        self.$inputState
            .removeDuplicates()
            .mainSink { [unowned self] inputState in
                self.updateLayout(for: inputState)
            }.store(in: &self.cancellables)
    }

    // MARK: - State Updates

    private func updateInputState(with numberOfLines: Int) {
        // When the text hits 3 lines, transition to the expanded state.
        // However don't automatically go back to the collapsed state when the line count is less than 3.
        guard numberOfLines > 2 else { return }
        self.inputState = .expanded
    }

    private func updateLayout(for inputState: InputState) {
        self.swipeInputView.updateLayout(for: inputState)
    }

    private func showDetail(shouldShow: Bool) {
        self.swipeInputView.showDetail(shouldShow: shouldShow)
    }

    func updateSwipeHint(shouldPlay: Bool) {
        self.hintAnimator.updateSwipeHint(shouldPlay: shouldPlay)
    }

    private func handleTextChange(_ text: String) {
        switch self.currentMessageKind {
        case .text(_):
            self.currentMessageKind = .text(text)
        case .photo(photo: let photo, _):
            self.currentMessageKind = .photo(photo: photo, body: text)
        case .video(video: let video, _):
            self.currentMessageKind = .video(video: video, body: text)
        default:
            break
        }

        // After the user enters text, the swipe hint can play to show them how to send it.
        let shouldPlay = !text.isEmpty && self.inputState == .collapsed
        self.hintAnimator.updateSwipeHint(shouldPlay: shouldPlay)
    }

    func updateInputType(with type: InputType) {
        self.swipeInputView.textView.updateInputView(type: type)
    }

    func resetInputViews() {
        self.inputState = .collapsed
        self.swipeInputView.textView.reset()
        self.swipeInputView.inputContainerView.alpha = 1
        self.swipeInputView.countView.alpha = 0.0
    }
}