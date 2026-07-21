//
//  ConversationSurfaceChrome.swift
//  Jibber
//

import Foundation
import Localization
import UIKit

/// Input contexts supported by the shared conversation composer. Production chat uses
/// ``chat`` while onboarding swaps the content hosted inside the same chrome.
enum ConversationComposerMode: String, Codable, CaseIterable, Sendable {
    case welcomeChoices
    case inviteCode
    case action
    case phone
    case verificationCode
    case name
    case faceCapture
    case review
    case chat
}

/// The common visual treatment for conversation input. The production XIB and the
/// programmatic onboarding composer both call this implementation so their bubble,
/// gutters, shadow, and color cannot drift apart.
enum ConversationComposerChrome {
    static let horizontalGutter: CGFloat = 16
    static let verticalGutter: CGFloat = 8
    static let collapsedHeight: CGFloat = 52

    @MainActor
    static func apply(to bubbleView: SpeechBubbleView) {
        bubbleView.tailLength = 0
        bubbleView.showShadow(withOffset: 8)
        bubbleView.setBubbleColor(ThemeColor.B1.color, animated: false)
    }
}

/// The state consumed by the common composer shell. Keeping the capability policy
/// beside the visual mode makes it impossible for an onboarding input to accidentally
/// inherit production-only affordances when its hosted content changes.
struct ConversationComposerShellConfiguration: Equatable, Sendable {
    let mode: ConversationComposerMode
    let capabilities: ConversationCapabilities
    let showsBack: Bool
    let showsPrimary: Bool

    static let productionChat = ConversationComposerShellConfiguration(
        mode: .chat,
        capabilities: .production,
        showsBack: false,
        showsPrimary: false
    )

    static func onboarding(
        mode: ConversationComposerMode
    ) -> ConversationComposerShellConfiguration {
        ConversationComposerShellConfiguration(
            mode: mode,
            capabilities: .onboarding,
            showsBack: false,
            showsPrimary: false
        )
    }

    /// Transitional overload for legacy onboarding call sites. Canonical
    /// conversation onboarding uses the control-free overload above.
    static func onboarding(
        mode: ConversationComposerMode,
        showsBack: Bool,
        showsPrimary: Bool
    ) -> ConversationComposerShellConfiguration {
        ConversationComposerShellConfiguration(
            mode: mode,
            capabilities: .onboarding,
            showsBack: showsBack,
            showsPrimary: showsPrimary
        )
    }
}

/// The single composer primitive used by both the production XIB and onboarding.
///
/// Production supplies its existing nib-owned text, attachment, typing, and unread
/// views. Onboarding supplies the same bubble and a contextual content host. The shell
/// applies one chrome implementation, owns mode/capability policy, and can temporarily
/// retain legacy controls without rendering them in the canonical flow. It does not own
/// supplied views, so the production accessory preserves its XIB constraints and
/// keyboard behavior.
@MainActor
final class ConversationComposerShell {
    @MainActor
    private final class CapabilityViewBinding {
        weak var view: UIView?
        let capability: ConversationCapabilities
        private var visibilityBeforeSuppression: Bool?

        init(view: UIView?, capability: ConversationCapabilities) {
            self.view = view
            self.capability = capability
        }

        func apply(_ capabilities: ConversationCapabilities) {
            guard let view else { return }

            if capabilities.contains(self.capability) {
                if let visibilityBeforeSuppression {
                    view.isVisible = visibilityBeforeSuppression
                    self.visibilityBeforeSuppression = nil
                }
            } else {
                if self.visibilityBeforeSuppression.isNil {
                    self.visibilityBeforeSuppression = view.isVisible
                }
                view.isVisible = false
            }
        }
    }

    private weak var bubbleView: SpeechBubbleView?
    private weak var contentView: UIView?
    private weak var backButton: ThemeButton?
    private weak var primaryButton: ThemeButton?
    private weak var hostedView: UIView?
    private var capabilityViewBindings: [CapabilityViewBinding]

    private(set) var configuration: ConversationComposerShellConfiguration

    var onBack: CompletionOptional = nil
    var onPrimary: CompletionOptional = nil

    init(
        bubbleView: SpeechBubbleView,
        contentView: UIView? = nil,
        backButton: ThemeButton? = nil,
        primaryButton: ThemeButton? = nil,
        attachmentView: UIView? = nil,
        expressionView: UIView? = nil,
        typingIndicatorView: UIView? = nil,
        unreadControlView: UIView? = nil,
        configuration: ConversationComposerShellConfiguration
    ) {
        self.bubbleView = bubbleView
        self.contentView = contentView
        self.backButton = backButton
        self.primaryButton = primaryButton
        self.configuration = configuration
        self.capabilityViewBindings = [
            CapabilityViewBinding(view: attachmentView, capability: .attachments),
            CapabilityViewBinding(view: expressionView, capability: .expressions),
            CapabilityViewBinding(view: typingIndicatorView, capability: .typingIndicators),
            CapabilityViewBinding(view: unreadControlView, capability: .unreadControls)
        ]

        ConversationComposerChrome.apply(to: bubbleView)

        backButton?.set(
            style: .image(
                symbol: .chevronDownCircle,
                palletteColors: [.white],
                pointSize: 22,
                backgroundColor: .B1
            )
        )
        backButton?.didSelect { [weak self] in
            self?.onBack?()
        }
        primaryButton?.didSelect { [weak self] in
            self?.onPrimary?()
        }

        self.applyCapabilityPolicy()
        self.applyControlVisibility()
    }

    var mode: ConversationComposerMode {
        self.configuration.mode
    }

    var capabilities: ConversationCapabilities {
        self.configuration.capabilities
    }

    func supports(_ capability: ConversationCapabilities) -> Bool {
        self.capabilities.contains(capability)
    }

    func configure(
        _ configuration: ConversationComposerShellConfiguration,
        primaryTitle: Localized? = nil
    ) {
        self.configuration = configuration
        self.applyCapabilityPolicy()
        self.applyControlVisibility()

        if let primaryTitle {
            self.primaryButton?.set(
                style: .custom(color: .D6, textColor: .white, text: primaryTitle)
            )
        }
    }

    func host(_ view: UIView?) {
        if self.hostedView !== view {
            self.hostedView?.removeFromSuperview()
        }
        self.hostedView = view

        guard let view, let contentView, view.superview !== contentView else { return }
        contentView.addSubview(view)
    }

    /// Lays out the programmatic shell. The production XIB deliberately does not call
    /// this method; its existing Auto Layout constraints remain the source of truth.
    func layoutProgrammaticShell(
        in bounds: CGRect,
        bubbleTopInset: CGFloat = ConversationComposerChrome.verticalGutter
    ) {
        guard let bubbleView else { return }

        let gutter = ConversationComposerChrome.horizontalGutter
        let buttonHeight = Theme.buttonHeight
        let showsBack = self.configuration.showsBack && self.backButton.exists
        let showsPrimary = self.configuration.showsPrimary && self.primaryButton.exists
        let backSize: CGFloat = showsBack ? buttonHeight : 0

        bubbleView.left = showsBack
            ? gutter + backSize + Theme.ContentOffset.short.value
            : gutter
        bubbleView.top = bubbleTopInset
        bubbleView.width = max(0, bounds.width - bubbleView.left - gutter)
        bubbleView.height = max(
            ConversationComposerChrome.collapsedHeight,
            bounds.height - bubbleTopInset - ConversationComposerChrome.verticalGutter
        )

        let controlCenterY = Self.controlCenterY(for: bubbleView.frame)
        self.backButton?.squaredSize = backSize
        self.backButton?.left = gutter
        self.backButton?.centerY = controlCenterY

        let primaryWidth: CGFloat = showsPrimary
            ? min(132, max(96, bubbleView.width * 0.36))
            : 0
        self.primaryButton?.size = CGSize(width: primaryWidth, height: buttonHeight)
        self.primaryButton?.pin(.right, offset: .standard)
        self.primaryButton?.centerY = controlCenterY - bubbleView.top

        guard let contentView else { return }
        contentView.pin(.left, offset: .standard)
        contentView.pin(.top, offset: .short)
        if self.configuration.mode == .faceCapture, showsPrimary {
            // Camera content needs the full bubble width. Keep the shared Back
            // and primary actions in one bottom row while reserving the space
            // above them for the existing face-capture controller.
            contentView.expand(
                .right,
                to: bubbleView.width - Theme.ContentOffset.standard.value
            )
            contentView.expand(
                .bottom,
                to: (self.primaryButton?.top ?? bubbleView.height)
                    - Theme.ContentOffset.short.value
            )
        } else {
            contentView.expand(
                .right,
                to: showsPrimary
                    ? (self.primaryButton?.left ?? bubbleView.width)
                        - Theme.ContentOffset.short.value
                    : bubbleView.width - Theme.ContentOffset.standard.value
            )
            contentView.expand(.bottom, padding: Theme.ContentOffset.short.value)
        }
        self.hostedView?.expandToSuperviewSize()
    }

    static func controlCenterY(for bubbleFrame: CGRect) -> CGFloat {
        bubbleFrame.maxY
            - Theme.ContentOffset.standard.value
            - Theme.buttonHeight.half
    }

    private func applyCapabilityPolicy() {
        self.capabilityViewBindings.forEach { binding in
            binding.apply(self.configuration.capabilities)
        }
    }

    private func applyControlVisibility() {
        self.backButton?.isVisible = self.configuration.showsBack
        self.primaryButton?.isVisible = self.configuration.showsPrimary
    }
}

enum ConversationVerticalSwipeDirection: Hashable, Sendable {
    case up
    case down
}

struct ConversationVerticalSwipeUpdate: Equatable, Sendable {
    let direction: ConversationVerticalSwipeDirection
    let translation: CGPoint
    let progress: CGFloat
    let isCommitReady: Bool
    let isVerticallyValid: Bool
}

/// Shared vertical swipe state machine for conversation composers.
///
/// It owns gesture intent, thresholding, cancellation, and the single-flight
/// commit gate. Consumers retain responsibility for payload validation and visual
/// previews through the callback surface, allowing production chat and onboarding
/// to share interaction physics without coupling onboarding to message delivery.
@MainActor
final class ConversationVerticalSwipeSubmissionController: NSObject,
                                                           UIGestureRecognizerDelegate {
    typealias CanBegin = (ConversationVerticalSwipeDirection) -> Bool
    typealias DidBegin = (ConversationVerticalSwipeDirection) -> Void
    typealias DidUpdate = (ConversationVerticalSwipeUpdate) -> Void
    typealias Commit = (ConversationVerticalSwipeDirection) async -> Bool
    typealias DidCancel = (ConversationVerticalSwipeDirection) -> Void
    typealias DidChangeCommitReadiness = (
        _ isReady: Bool,
        _ direction: ConversationVerticalSwipeDirection
    ) -> Void
    typealias CommitReadinessEvaluator = (
        _ translation: CGPoint,
        _ direction: ConversationVerticalSwipeDirection,
        _ defaultReadiness: Bool
    ) -> Bool

    let panGestureRecognizer: UIPanGestureRecognizer

    var canBegin: CanBegin?
    var didBegin: DidBegin?
    var didUpdate: DidUpdate?
    var commit: Commit?
    var didCancel: DidCancel?
    /// Called only when the threshold readiness changes. This is the appropriate
    /// hook for caller-owned haptic and visual feedback.
    var didChangeCommitReadiness: DidChangeCommitReadiness?
    /// Production chat can preserve its Time Machine drop-zone geometry while
    /// still sharing this driver's intent, cancellation, and single-flight
    /// lifecycle. Onboarding uses the default distance threshold.
    var commitReadinessEvaluator: CommitReadinessEvaluator?

    var commitDistance: CGFloat
    var maximumHorizontalTravel: CGFloat
    var maximumHorizontalRatio: CGFloat
    /// Production's legacy recognizer intentionally begins after a stationary
    /// press so it can reveal the message preview before movement begins.
    var allowsStationaryBegin = false

    private(set) var isCommitting = false
    private var activeDirection: ConversationVerticalSwipeDirection?
    private var isCommitReady = false

    var isEnabled: Bool {
        get { self.panGestureRecognizer.isEnabled }
        set { self.panGestureRecognizer.isEnabled = newValue }
    }

    init(
        attachingTo view: UIView,
        panGestureRecognizer: UIPanGestureRecognizer = UIPanGestureRecognizer(),
        commitDistance: CGFloat = 96,
        maximumHorizontalTravel: CGFloat = 44,
        maximumHorizontalRatio: CGFloat = 0.85
    ) {
        self.commitDistance = max(1, commitDistance)
        self.maximumHorizontalTravel = max(0, maximumHorizontalTravel)
        self.maximumHorizontalRatio = max(0, maximumHorizontalRatio)
        self.panGestureRecognizer = panGestureRecognizer
        super.init()

        self.panGestureRecognizer.addTarget(
            self,
            action: #selector(self.handlePan(_:))
        )
        self.panGestureRecognizer.delegate = self
        self.panGestureRecognizer.cancelsTouchesInView = false
        self.panGestureRecognizer.delaysTouchesBegan = false
        self.panGestureRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(self.panGestureRecognizer)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !self.isCommitting,
              self.commit != nil,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return false
        }

        let velocity = pan.velocity(in: pan.view)
        let stationaryDirection: ConversationVerticalSwipeDirection? =
            self.allowsStationaryBegin && velocity == .zero ? .up : nil
        guard (abs(velocity.y) > abs(velocity.x) || stationaryDirection != nil),
              let direction = Self.direction(forVerticalValue: velocity.y)
                ?? stationaryDirection,
              self.canBegin?(direction) ?? true else {
            return false
        }
        return true
    }

    func cancelActiveSwipe() {
        guard let direction = self.activeDirection else { return }
        self.didCancel?(direction)
        self.resetGestureState(for: direction)
        self.panGestureRecognizer.isEnabled = false
        self.panGestureRecognizer.isEnabled = true
    }

    /// Runs the same validated, single-flight commit path without a physical
    /// gesture. This is used by VoiceOver and Switch Control custom actions.
    @discardableResult
    func submit(_ direction: ConversationVerticalSwipeDirection) -> Bool {
        guard !self.isCommitting,
              self.isEnabled,
              self.canBegin?(direction) ?? true,
              let commit = self.commit else {
            return false
        }

        self.didBegin?(direction)
        self.beginCommit(direction: direction, commit: commit)
        return true
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: pan.view)

        switch pan.state {
        case .began:
            let velocity = pan.velocity(in: pan.view)
            guard let direction = Self.direction(forVerticalValue: velocity.y)
                    ?? (self.allowsStationaryBegin ? .up : nil) else {
                return
            }
            self.activeDirection = direction
            self.didBegin?(direction)
            self.publishUpdate(translation: translation, direction: direction)
        case .changed:
            guard let direction = self.activeDirection else { return }
            self.publishUpdate(translation: translation, direction: direction)
        case .ended:
            guard let direction = self.activeDirection else { return }
            let update = self.makeUpdate(
                translation: translation,
                direction: direction
            )
            self.publish(update)

            guard update.isCommitReady,
                  let commit = self.commit else {
                self.didCancel?(direction)
                self.resetGestureState(for: direction)
                return
            }

            self.resetGestureState(for: direction)
            self.beginCommit(direction: direction, commit: commit)
        case .cancelled, .failed:
            guard let direction = self.activeDirection else { return }
            self.didCancel?(direction)
            self.resetGestureState(for: direction)
        case .possible:
            break
        @unknown default:
            if let direction = self.activeDirection {
                self.didCancel?(direction)
                self.resetGestureState(for: direction)
            }
        }
    }

    private func publishUpdate(
        translation: CGPoint,
        direction: ConversationVerticalSwipeDirection
    ) {
        self.publish(self.makeUpdate(translation: translation, direction: direction))
    }

    private func publish(_ update: ConversationVerticalSwipeUpdate) {
        if update.isCommitReady != self.isCommitReady {
            self.isCommitReady = update.isCommitReady
            self.didChangeCommitReadiness?(
                update.isCommitReady,
                update.direction
            )
        }
        self.didUpdate?(update)
    }

    private func makeUpdate(
        translation: CGPoint,
        direction: ConversationVerticalSwipeDirection
    ) -> ConversationVerticalSwipeUpdate {
        let directedDistance: CGFloat
        switch direction {
        case .up:
            directedDistance = max(0, -translation.y)
        case .down:
            directedDistance = max(0, translation.y)
        }

        let maximumAllowedHorizontalTravel = max(
            self.maximumHorizontalTravel,
            directedDistance * self.maximumHorizontalRatio
        )
        let isVerticallyValid = abs(translation.x) <= maximumAllowedHorizontalTravel
        let progress = isVerticallyValid
            ? clamp(directedDistance / self.commitDistance, 0, 1)
            : 0

        let defaultReadiness = isVerticallyValid && progress >= 1
        let isCommitReady = self.commitReadinessEvaluator?(
            translation,
            direction,
            defaultReadiness
        ) ?? defaultReadiness

        return ConversationVerticalSwipeUpdate(
            direction: direction,
            translation: translation,
            progress: progress,
            isCommitReady: isVerticallyValid && isCommitReady,
            isVerticallyValid: isVerticallyValid
        )
    }

    private func resetGestureState(for direction: ConversationVerticalSwipeDirection) {
        if self.isCommitReady {
            self.didChangeCommitReadiness?(false, direction)
        }
        self.activeDirection = nil
        self.isCommitReady = false
    }

    private func beginCommit(
        direction: ConversationVerticalSwipeDirection,
        commit: @escaping Commit
    ) {
        self.isCommitting = true
        Task { @MainActor [weak self] in
            let didCommit = await commit(direction)
            guard let self else { return }
            self.isCommitting = false
            if !didCommit {
                self.didCancel?(direction)
            }
        }
    }

    private static func direction(
        forVerticalValue value: CGFloat
    ) -> ConversationVerticalSwipeDirection? {
        guard value != 0 else { return nil }
        return value < 0 ? .up : .down
    }
}

/// Header geometry shared by the normal conversation header and onboarding. Consumers
/// provide the centered content (people or progress) and optional edge controls.
final class ConversationHeaderChromeView: BaseView {
    let leadingContentView = UIView()
    let centeredContentView = UIView()
    let trailingContentView = UIView()

    override func initializeSubviews() {
        super.initializeSubviews()

        self.clipsToBounds = false
        self.addSubview(self.leadingContentView)
        self.addSubview(self.centeredContentView)
        self.addSubview(self.trailingContentView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let edge: CGFloat = 44
        self.leadingContentView.frame = CGRect(x: 0, y: 0, width: edge, height: edge)
        self.leadingContentView.centerY = self.halfHeight

        self.trailingContentView.frame = CGRect(
            x: max(0, self.width - edge),
            y: 0,
            width: edge,
            height: edge
        )
        self.trailingContentView.centerY = self.halfHeight

        let centeredWidth = max(
            0,
            self.width - (edge + Theme.ContentOffset.standard.value).doubled
        )
        self.centeredContentView.size = CGSize(width: centeredWidth, height: edge)
        self.centeredContentView.centerOnXAndY()
    }
}

/// Independent line tracks used in place of conversation participants during
/// onboarding. `progress` is continuous so each line fills and rewinds with the Time
/// Machine scroll position rather than jumping only after a step commits. Accessibility
/// is updated separately at snap time so continuous scrolling does not announce a
/// stream of intermediate values.
final class ConversationProgressSegmentsView: BaseView {
    private(set) var segmentCount: Int
    private(set) var progress: CGFloat = 1
    private(set) var settledStep: Int = 1
    private var trackViews: [UIView] = []
    private var fillViews: [UIView] = []

    init(segmentCount: Int = 5) {
        self.segmentCount = max(1, segmentCount)
        super.init()

        self.isAccessibilityElement = true
        self.accessibilityLabel = "Onboarding progress"
        self.accessibilityTraits = .staticText
        self.accessibilityValue = "Step 1 of \(self.segmentCount)"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeSubviews() {
        super.initializeSubviews()

        for _ in 0..<self.segmentCount {
            let track = UIView()
            track.backgroundColor = ThemeColor.B1.color
            track.layer.cornerRadius = 1.5
            track.clipsToBounds = true
            self.addSubview(track)
            self.trackViews.append(track)

            let fill = UIView()
            fill.backgroundColor = ThemeColor.D6.color
            fill.layer.cornerRadius = 1.5
            track.addSubview(fill)
            self.fillViews.append(fill)
        }
    }

    func set(progress: CGFloat, animated: Bool) {
        // Welcome is meaningful progress, so the visual surface never renders 0%.
        self.progress = clamp(progress, 1, CGFloat(self.segmentCount))

        self.setNeedsLayout()
        guard animated else {
            self.layoutIfNeeded()
            return
        }
        UIView.animate(withDuration: Theme.animationDurationFast) {
            self.layoutIfNeeded()
        }
    }

    /// Commits the accessibility value after the Time Machine snaps. Continuous
    /// visual updates should continue to use ``set(progress:animated:)`` only.
    func setSettledStep(_ step: Int, announce: Bool = false) {
        let clampedStep = min(self.segmentCount, max(1, step))
        let value = "Step \(clampedStep) of \(self.segmentCount)"
        if clampedStep != self.settledStep || self.accessibilityValue == nil {
            self.settledStep = clampedStep
            self.accessibilityValue = value
        }
        if announce {
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(self.accessibilityLabel ?? "Onboarding progress"), \(value)"
            )
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard self.segmentCount > 0 else { return }

        let gap: CGFloat = 12
        let lineHeight: CGFloat = 3
        let totalGap = gap * CGFloat(self.segmentCount - 1)
        let segmentWidth = max(0, (self.width - totalGap) / CGFloat(self.segmentCount))

        for index in 0..<self.segmentCount {
            let x = CGFloat(index) * (segmentWidth + gap)
            let track = self.trackViews[index]
            track.frame = CGRect(
                x: x,
                y: self.halfHeight - lineHeight.half,
                width: segmentWidth,
                height: lineHeight
            )

            let fraction = clamp(self.progress - CGFloat(index), 0, 1)
            self.fillViews[index].frame = CGRect(
                x: 0,
                y: 0,
                width: segmentWidth * fraction,
                height: lineHeight
            )
        }
    }
}

/// Programmatic sibling of the production input accessory. It deliberately hosts the
/// step controller rather than recreating phone/name/photo controls, while sharing the
/// production conversation bubble chrome.
final class ConversationComposerShellView: BaseView {
    let backButton = ThemeButton()
    let bubbleView = SpeechBubbleView(orientation: .up, bubbleColor: .B1)
    let contentView = UIView()
    let primaryButton = ThemeButton()
    let contextIndicatorView = ConversationTypingIndicatorView()

    private var composerShell: ConversationComposerShell!
    private var swipeSubmissionController: ConversationVerticalSwipeSubmissionController!
    private var isSwipeUpSubmissionEnabled = true
    private var isSwipeDownSubmissionEnabled = true
    private let swipeImpactFeedback = UIImpactFeedbackGenerator(style: .rigid)
    private var swipeUpAccessibilityName: String?
    private var swipeDownAccessibilityName: String?

    var mode: ConversationComposerMode {
        self.composerShell.mode
    }

    var capabilities: ConversationCapabilities {
        self.composerShell.capabilities
    }

    var onBack: CompletionOptional = nil
    var onPrimary: CompletionOptional = nil
    /// Immediate callbacks used by the existing onboarding controller, whose
    /// request state machine disables interaction as soon as submission begins.
    var onSwipeUp: CompletionOptional = nil
    var onSwipeDown: CompletionOptional = nil
    /// Optional async commits for consumers that want the shared driver itself
    /// to retain the single-flight gate through request completion.
    var onSwipeUpCommit: (() async -> Bool)?
    var onSwipeDownCommit: (() async -> Bool)?
    var onSwipeBegin: ((ConversationVerticalSwipeDirection) -> Void)?
    var onSwipeUpdate: ((ConversationVerticalSwipeUpdate) -> Void)?
    var onSwipeCancel: ((ConversationVerticalSwipeDirection) -> Void)?
    var onSwipeCommitReadinessChanged: ((
        _ isReady: Bool,
        _ direction: ConversationVerticalSwipeDirection
    ) -> Void)?

    override func initializeSubviews() {
        super.initializeSubviews()

        self.backgroundColor = .clear

        self.addSubview(self.contextIndicatorView)
        self.addSubview(self.backButton)
        self.addSubview(self.bubbleView)
        self.bubbleView.addSubview(self.contentView)
        self.bubbleView.addSubview(self.primaryButton)

        self.composerShell = ConversationComposerShell(
            bubbleView: self.bubbleView,
            contentView: self.contentView,
            backButton: self.backButton,
            primaryButton: self.primaryButton,
            configuration: .onboarding(mode: .action)
        )
        self.backButton.accessibilityLabel = "Previous onboarding step"
        self.backButton.accessibilityIdentifier = "onboarding.previous"
        self.composerShell.onBack = { [weak self] in
            self?.onBack?()
        }
        self.composerShell.onPrimary = { [weak self] in
            self?.onPrimary?()
        }

        self.swipeSubmissionController = ConversationVerticalSwipeSubmissionController(
            attachingTo: self
        )
        self.swipeSubmissionController.canBegin = { [weak self] direction in
            guard let self else { return false }
            switch direction {
            case .up:
                return self.isSwipeUpSubmissionEnabled
                    && (self.onSwipeUp != nil || self.onSwipeUpCommit != nil)
            case .down:
                return self.isSwipeDownSubmissionEnabled
                    && (self.onSwipeDown != nil || self.onSwipeDownCommit != nil)
            }
        }
        self.swipeSubmissionController.didBegin = { [weak self] direction in
            self?.swipeImpactFeedback.prepare()
            self?.onSwipeBegin?(direction)
        }
        self.swipeSubmissionController.didUpdate = { [weak self] update in
            self?.onSwipeUpdate?(update)
        }
        self.swipeSubmissionController.commit = { [weak self] direction in
            guard let self else { return false }
            switch direction {
            case .up:
                if let onSwipeUpCommit = self.onSwipeUpCommit {
                    return await onSwipeUpCommit()
                }
                self.onSwipeUp?()
                return self.onSwipeUp != nil
            case .down:
                if let onSwipeDownCommit = self.onSwipeDownCommit {
                    return await onSwipeDownCommit()
                }
                self.onSwipeDown?()
                return self.onSwipeDown != nil
            }
        }
        self.swipeSubmissionController.didCancel = { [weak self] direction in
            self?.onSwipeCancel?(direction)
        }
        self.swipeSubmissionController.didChangeCommitReadiness = {
            [weak self] isReady, direction in
            if isReady {
                self?.swipeImpactFeedback.impactOccurred(
                    intensity: direction == .up ? 0.6 : 0.4
                )
            }
            self?.onSwipeCommitReadinessChanged?(isReady, direction)
        }
    }

    /// Canonical onboarding configuration. It intentionally has no visible
    /// Back or primary controls; taps choose Welcome options and vertical swipes
    /// submit contextual inputs.
    func configure(mode: ConversationComposerMode) {
        self.composerShell.configure(.onboarding(mode: mode))
        self.primaryButton.accessibilityIdentifier = nil
        self.setNeedsLayout()
    }

    func configure(
        mode: ConversationComposerMode,
        primaryTitle: Localized?,
        showsBack: Bool,
        showsPrimary: Bool
    ) {
        self.composerShell.configure(
            .onboarding(
                mode: mode,
                showsBack: showsBack,
                showsPrimary: showsPrimary
            ),
            primaryTitle: primaryTitle
        )
        self.primaryButton.accessibilityIdentifier = "onboarding.primary.\(mode.rawValue)"
        self.setNeedsLayout()
    }

    func host(_ view: UIView?) {
        self.composerShell.host(view)
        self.setNeedsLayout()
    }

    func setContextText(
        _ text: String?,
        highlights: [String] = [],
        animated: Bool = true
    ) {
        self.contextIndicatorView.setText(
            text,
            highlights: highlights,
            animated: animated
        )
        self.setNeedsLayout()
    }

    func setSwipeSubmissionEnabled(_ isEnabled: Bool) {
        self.isSwipeUpSubmissionEnabled = isEnabled
        self.isSwipeDownSubmissionEnabled = isEnabled
    }

    func setSwipeSubmissionEnabled(
        _ isEnabled: Bool,
        for direction: ConversationVerticalSwipeDirection
    ) {
        switch direction {
        case .up:
            self.isSwipeUpSubmissionEnabled = isEnabled
        case .down:
            self.isSwipeDownSubmissionEnabled = isEnabled
        }
    }

    func setSwipeInteractionEnabled(_ isEnabled: Bool) {
        self.swipeSubmissionController.isEnabled = isEnabled
    }

    func setSwipeAccessibilityActions(
        up upName: String?,
        down downName: String? = nil
    ) {
        self.swipeUpAccessibilityName = upName
        self.swipeDownAccessibilityName = downName
        self.updateSwipeAccessibilityActions()
    }

    func setPrimaryEnabled(_ isEnabled: Bool) {
        self.primaryButton.isEnabled = isEnabled
        self.primaryButton.isUserInteractionEnabled = isEnabled
        // Compatibility for the pre-swipe onboarding controller. Once its
        // visible primary control is removed, the same validity source gates
        // the swipe submission path.
        self.setSwipeSubmissionEnabled(isEnabled)
    }

    func setControlsEnabled(_ isEnabled: Bool) {
        self.backButton.isEnabled = isEnabled
        self.backButton.isUserInteractionEnabled = isEnabled
        self.primaryButton.isEnabled = isEnabled
        self.primaryButton.isUserInteractionEnabled = isEnabled
        self.setSwipeInteractionEnabled(isEnabled)
    }

    func handlePrimaryEvent(_ status: EventStatus) async {
        await self.primaryButton.handleEvent(status: status)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let hasContext = self.contextIndicatorView.hasText
        let indicatorHeight: CGFloat = hasContext ? 16 : 0
        let indicatorGap: CGFloat = hasContext ? 4 : 0
        let bubbleTopInset = hasContext
            ? indicatorHeight + indicatorGap
            : ConversationComposerChrome.verticalGutter

        self.contextIndicatorView.isHidden = !hasContext
        self.contextIndicatorView.frame = CGRect(
            x: ConversationComposerChrome.horizontalGutter
                + Theme.ContentOffset.standard.value,
            y: 0,
            width: max(
                0,
                self.width
                    - ConversationComposerChrome.horizontalGutter.doubled
                    - Theme.ContentOffset.standard.value.doubled
            ),
            height: indicatorHeight
        )
        self.composerShell.layoutProgrammaticShell(
            in: self.bounds,
            bubbleTopInset: bubbleTopInset
        )
    }

    private func updateSwipeAccessibilityActions() {
        var actions: [UIAccessibilityCustomAction] = []
        if let swipeUpAccessibilityName {
            actions.append(
                UIAccessibilityCustomAction(
                    name: swipeUpAccessibilityName,
                    target: self,
                    selector: #selector(self.performSwipeUpAccessibilityAction)
                )
            )
        }
        if let swipeDownAccessibilityName {
            actions.append(
                UIAccessibilityCustomAction(
                    name: swipeDownAccessibilityName,
                    target: self,
                    selector: #selector(self.performSwipeDownAccessibilityAction)
                )
            )
        }
        self.accessibilityCustomActions = actions.isEmpty ? nil : actions
    }

    @objc private func performSwipeUpAccessibilityAction() -> Bool {
        self.swipeSubmissionController.submit(.up)
    }

    @objc private func performSwipeDownAccessibilityAction() -> Bool {
        self.swipeSubmissionController.submit(.down)
    }
}
