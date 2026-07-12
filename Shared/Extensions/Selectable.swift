//
//  Selectable.swift
//  Benji
//
//  Created by Benji Dodgson on 12/8/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import UIKit

@MainActor
protocol Selectable {
    func didSelect(useImpact: Bool, _ completion: CompletionOptional)
}

// These values are never read or mutated; their stable addresses are the
// Objective-C associated-object keys used by main-actor UIKit code below.
nonisolated(unsafe) private var selectionHandlerKey: UInt8 = 0
nonisolated(unsafe) private var didSelectHandlerKey: UInt8 = 0
nonisolated(unsafe) private var actionHandlerKey: UInt = 0
extension Selectable where Self: UIControl {

    private(set) var selectionImpact: UIImpactFeedbackGenerator? {
        get {
            return self.getAssociatedObject(&selectionHandlerKey)
        }
        set {
            self.setAssociatedObject(key: &selectionHandlerKey, value: newValue)
        }
    }
    
    private(set) var action: UIAction? {
        get {
            return self.getAssociatedObject(&actionHandlerKey)
        }
        set {
            self.setAssociatedObject(key: &actionHandlerKey, value: newValue)
        }
    }

    var isActive: Bool {
        return !self.selectionImpact.isNil
    }

    func didSelect(_ completion: CompletionOptional) {
        if let action = self.action {
            self.removeAction( action, for: .touchUpInside)
        }
        
        self.selectionImpact = UIImpactFeedbackGenerator()
        self.action = UIAction { action in
            completion?()
        }

        self.addAction(self.action!, for: .touchUpInside)
    }
}

// See the associated-object key lifetime note above.
nonisolated(unsafe) private var tapHandlerKey: UInt = 0
extension Selectable where Self: UIView {

    private(set) var tapRecognizer: UITapGestureRecognizer? {
        get {
            return self.getAssociatedObject(&tapHandlerKey)
        }
        set {
            self.setAssociatedObject(key: &tapHandlerKey, value: newValue)
        }
    }
    
    private(set) var doubleTapRecognizer: UITapGestureRecognizer? {
        get {
            return self.getAssociatedObject(&tapHandlerKey)
        }
        set {
            self.setAssociatedObject(key: &tapHandlerKey, value: newValue)
        }
    }

    private(set) var selectionImpact: UIImpactFeedbackGenerator? {
        get {
            return self.getAssociatedObject(&selectionHandlerKey)
        }
        set {
            self.setAssociatedObject(key: &selectionHandlerKey, value: newValue)
        }
    }

    func didSelect(useImpact: Bool = true, _ completion: CompletionOptional) {
        self.selectionImpact = UIImpactFeedbackGenerator()

        // Remove the previous tap gesture recognizer so we don't call did select twice.
        if let tapRecognizer = self.tapRecognizer {
            self.removeGestureRecognizer(tapRecognizer)
        }
        
        let tapRecognizer = TapGestureRecognizer(taps: 1) { [unowned self] _ in
            if useImpact {
                self.selectionImpact?.impactOccurred()
            }
            completion?()
        }
        self.addGestureRecognizer(tapRecognizer)
        self.tapRecognizer = tapRecognizer
    }
    
    func onDoubleTap(_ completion: CompletionOptional) {
        self.selectionImpact = UIImpactFeedbackGenerator()

        // Remove the previous tap gesture recognizer so we don't call did select twice.
        if let tapRecognizer = self.doubleTapRecognizer {
            self.removeGestureRecognizer(tapRecognizer)
        }
        
        let tapRecognizer = TapGestureRecognizer(taps: 2) { [unowned self] _ in
            self.selectionImpact?.impactOccurred()
            completion?()
        }
        self.addGestureRecognizer(tapRecognizer)
        self.doubleTapRecognizer = tapRecognizer
    }
}

class TapGestureRecognizer: UITapGestureRecognizer {
    private var action: (UITapGestureRecognizer) -> Void

    init(taps: Int = 1, action: @escaping (UITapGestureRecognizer) -> Void) {
        self.action = action
        super.init(target: nil, action: nil)
        self.numberOfTapsRequired = taps
        self.addTarget(self, action: #selector(execute))
    }

    @objc private func execute() {
        self.action(self)
    }
}

class LongpressGestureRecognizer: UILongPressGestureRecognizer {
    private var action: ((UILongPressGestureRecognizer) -> Void)?

    init(action: ((UILongPressGestureRecognizer) -> Void)?) {
        self.action = action
        super.init(target: nil, action: nil)
        self.allowableMovement = 30
        self.addTarget(self, action: #selector(execute))
    }

    @objc private func execute() {
        self.action?(self)
    }
}

class PanGestureRecognizer: UIPanGestureRecognizer {
    private var action: (UIPanGestureRecognizer) -> Void

    init(action: @escaping (UIPanGestureRecognizer) -> Void) {
        self.action = action
        super.init(target: nil, action: nil)
        self.addTarget(self, action: #selector(execute))
    }

    @objc private func execute() {
        self.action(self)
    }
}

/// Similar to pan gesture recognizer except that the begin state is triggered after a short delay, even if the touch doesn't move.
class SwipeGestureRecognizer: UIPanGestureRecognizer {

    var touchesDidBegin: CompletionOptional = nil

    var beginDelay: TimeInterval = 0.2

    private var action: (UIPanGestureRecognizer) -> Void

    init(action: @escaping (UIPanGestureRecognizer) -> Void) {
        self.action = action

        super.init(target: nil, action: nil)

        self.addTarget(self, action: #selector(execute))
    }

    @objc private func execute() {
        self.action(self)
    }

    private var beginStateTask: Task<Void, Never>?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        self.beginStateTask?.cancel()

        self.beginStateTask = Task { [weak self] in
            await Task.sleep(seconds: self?.beginDelay ?? 0)

            guard !Task.isCancelled else { return }

            self?.touchesDidBegin?()
            self?.state = .began
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)

        self.beginStateTask?.cancel()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)

        self.beginStateTask?.cancel()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)

        self.beginStateTask?.cancel()
    }
}
