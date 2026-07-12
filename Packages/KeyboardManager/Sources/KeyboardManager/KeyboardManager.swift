import Combine
import UIKit
import Foundation

public class KeyboardManager {

    public static let shared = KeyboardManager()

    @Published public var currentEvent: KeyboardEvent = .none
    @Published public var cachedKeyboardEndFrame: CGRect = .zero
    public var isKeyboardShowing: Bool = false
    
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.addKeyboardObservers()
    }

    private func addKeyboardObservers() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .mainSink { (notification) in
                guard !self.isKeyboardShowing else { return }

                let inputAccessoryHeight = self.getInputAccessoryHeight()

                if notification.keyboardEndFrame.height > inputAccessoryHeight {
                    self.currentEvent = .willShow(notification)
                    self.cachedKeyboardEndFrame = notification.keyboardEndFrame
                }
            }.store(in: &self.cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)
            .mainSink { (notification) in
                guard !self.isKeyboardShowing else { return }

                let inputAccessoryHeight = self.getInputAccessoryHeight()

                if notification.keyboardEndFrame.height > inputAccessoryHeight {
                    self.currentEvent = .didShow(notification)
                    self.cachedKeyboardEndFrame = notification.keyboardEndFrame
                    self.isKeyboardShowing = true
                }
            }.store(in: &self.cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .mainSink { (notification) in
                guard self.isKeyboardShowing else { return }

                let inputAccessoryHeight = self.getInputAccessoryHeight()
                let keyboardFrameVisibleHeight = self.getKeyboardFrameVisibleHeight(for: notification)

                if keyboardFrameVisibleHeight <= inputAccessoryHeight {
                    self.currentEvent = .willHide(notification)
                    self.cachedKeyboardEndFrame = notification.keyboardEndFrame
                }

            }.store(in: &self.cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)
            .mainSink { (notification) in
                guard self.isKeyboardShowing else { return }

                let inputAccessoryHeight = self.getInputAccessoryHeight()
                let keyboardFrameVisibleHeight = self.getKeyboardFrameVisibleHeight(for: notification)

                if keyboardFrameVisibleHeight <= inputAccessoryHeight {
                    self.currentEvent = .didHide(notification)
                    self.cachedKeyboardEndFrame = notification.keyboardEndFrame

                    self.isKeyboardShowing = false
                }
            }.store(in: &self.cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .mainSink { (notification) in
                self.currentEvent = .willChangeFrame(notification)
                self.cachedKeyboardEndFrame = notification.keyboardEndFrame
            }.store(in: &self.cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)
            .mainSink { (notification) in
                self.currentEvent = .didChangeFrame(notification)
                self.cachedKeyboardEndFrame = notification.keyboardEndFrame
            }.store(in: &self.cancellables)
    }

    private func getInputAccessoryHeight() -> CGFloat {
        var inputAccessoryHeight: CGFloat = 0
        guard let responder = UIResponder.firstResponder else {
            return inputAccessoryHeight
        }
        if let inputAccessoryView = responder.inputAccessoryView {
            inputAccessoryHeight = inputAccessoryView.height
        } else if let inputAccessoryView = responder.inputAccessoryViewController?.view {
            inputAccessoryHeight = inputAccessoryView.height
        }

        return inputAccessoryHeight
    }

    private func getKeyboardFrameVisibleHeight(for notification: NotificationCenter.Publisher.Output)
    -> CGFloat {

        let keyboardFrame = notification.keyboardEndFrame
        guard let window = (UIResponder.firstResponder as? UIView)?.window else {
            return keyboardFrame.height
        }
        let frameInWindow = window.convert(keyboardFrame, from: nil)
        return max(0, window.bounds.maxY - frameInWindow.minY)
    }
}

