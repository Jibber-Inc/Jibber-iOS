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
import KeyboardManager

@MainActor
protocol SwipeableInputAccessoryViewControllerDelegate: AnyObject {
    /// The accessory has begun a swipe interaction.
    func swipeableInputAccessoryDidBeginSwipe(_ controller: SwipeableInputAccessoryViewController)
    /// The accessory view wants to send the sendable with the preview with the specified frame.
    /// The delegate should return true if the sendable was sent.
    func swipeableInputAccessory(_ controller: SwipeableInputAccessoryViewController,
                                 triggeredSendFor sendable: MessageSendable,
                                 withPreviewFrame frame: CGRect) async -> Bool
    /// The accessory view finished its swipe interaction.
    func swipeableInputAccessoryDidFinishSwipe(_ controller: SwipeableInputAccessoryViewController)
}

class SwipeableInputAccessoryViewController: UIInputViewController {

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
    
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Message State

    var editableMessage: Messageable?
    @Published var currentMessageKind: MessageKind = .text(String())
    var sendable: SendableObject?

    // MARK: - Layout/Animation Properties

    private lazy var hintAnimator = SwipeInputHintAnimator(swipeInputView: self.swipeInputView)

    // MARK: BaseView Setup and Layout

    override func loadView() {
        self.view = self.swipeInputView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupGestures()
        self.setupHandlers()
    }

    private lazy var inputFieldTapRecognizer = TapGestureRecognizer(taps: 1) { [unowned self] recognizer in
        self.handleInputTap()
    }
    private lazy var backgroundTapRecognizer = TapGestureRecognizer { [unowned self] recognizer in
        self.handleBackgroundTap()
    }

    func setupGestures() {
        self.swipeInputView.addView.didSelectRemove = { [unowned self] in
            self.currentMessageKind = .text(self.swipeInputView.textView.text)
        }
        
        self.panGestureHandler.install()
        self.swipeInputView.gestureButton.addGestureRecognizer(self.inputFieldTapRecognizer)
        self.swipeInputView.doneButton.didSelect { [unowned self] in
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
                    self.swipeInputView.setShowMessageDetailOptions(shouldShowDetail: true, showAvatar: false)
                    self.hintAnimator.updateSwipeHint(shouldPlay: false)
                    self.swipeInputView.updateLayout(for: self.inputState)
                case .didShow:
                    break 
                case .willHide:
                    self.swipeInputView.setShowMessageDetailOptions(shouldShowDetail: true, showAvatar: true)
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
            self.swipeInputView.characterCountView.update(with: text.count,
                                                 max: self.swipeInputView.textView.maxLength)
        }.store(in: &self.cancellables)

        self.swipeInputView.textView.$isEditing.mainSink { [unowned self] isEditing in
            // If we are editing, a double tap should trigger the expanded state.
            // If we're not editing, it takes 1 tap to start.
            self.inputFieldTapRecognizer.numberOfTapsRequired = isEditing ? 2 : 1
        }.store(in: &self.cancellables)

        self.$inputState
            .mainSink { [unowned self] inputState in
                self.swipeInputView.updateLayout(for: inputState)
            }.store(in: &self.cancellables)
        
        self.$currentMessageKind
            .removeDuplicates()
            .mainSink { [unowned self] kind in
                self.updateLayout(for: kind)
            }.store(in: &self.cancellables)
    }

    // MARK: - State Updates
    
    /// Used to update the layout when the message kind is changed.
    private func updateLayout(for kind: MessageKind) {
        switch kind {
        case .text(_):
            self.swipeInputView.addView.configure(with: [])
        case .attributedText(_):
            self.swipeInputView.addView.configure(with: [])
        case .photo(photo: let item, _):
            self.swipeInputView.addView.configure(with: [item])
        case .video(video: let item, _):
            self.swipeInputView.addView.configure(with: [item])
        case .media(items: let items, _):
            self.swipeInputView.addView.configure(with: items)
        case .location(_):
            break
        case .emoji(_):
            break
        case .audio(_):
            break
        case .contact(_):
            break
        case .link(_, _):
            self.swipeInputView.addView.configure(with: [])
        }
    }

    private func updateInputState(with numberOfLines: Int) {
        guard self.inputState != .expanded else { return }
        // When the text hits 4 lines, transition to the expanded state.
        // However don't automatically go back to the collapsed state when the line count is less than 3.
        if numberOfLines > 4 {
            self.inputState = .expanded
        } else {
            self.inputState = .collapsed
        }
    }

    func updateSwipeHint(shouldPlay: Bool) {
        self.hintAnimator.updateSwipeHint(shouldPlay: shouldPlay)
    }

    private func handleTextChange(_ text: String) {
        switch self.currentMessageKind {
        case .text, .link:
            // If there's URL in the text, then this becomes a link message.
            if text.isSingleLink, let url = text.getURLs().first {
                self.currentMessageKind = .link(url: url, stringURL: text)
            } else {
                // No URL means we're just sending plain text.
                self.currentMessageKind = .text(text)
            }
        case .photo(photo: let photo, _):
            self.currentMessageKind = .photo(photo: photo, body: text)
        case .video(video: let video, _):
            self.currentMessageKind = .video(video: video, body: text)
        case .media(items: let items, body: _):
            self.currentMessageKind = .media(items: items, body: text)
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
        self.swipeInputView.characterCountView.alpha = 0.0        
        self.currentMessageKind = .text("")
    }
}
