//
//  UserOnboardingViewController.swift
//  Jibber
//

import Combine
import Coordinator
import Foundation
import KeyboardManager
import Localization
import ParseCore
import UIKit

#if APPCLIP
private typealias OnboardingConversationMessageCellBase = ConversationMessagePresentationCell
#else
/// The full app uses the exact rich production message cell after authentication.
/// Its interaction layers are disabled through the onboarding capability policy.
private typealias OnboardingConversationMessageCellBase = MessageCell
#endif

/// Onboarding uses the production presentation cell without adding badges or
/// disclosures. Automated-message metadata remains available to the server but is
/// deliberately not rendered in the onboarding conversation.
private final class OnboardingConversationMessageCell: OnboardingConversationMessageCellBase {}

/// The onboarding host is a real conversation surface: the shared production Time
/// Machine rail occupies the center, production header geometry owns the progress slot,
/// and the shared conversation composer chrome hosts the current input controller.
class UserOnboardingViewController: ViewController {
    private static let timelineCellReuseIdentifier = "OnboardingConversationMessageCell"

    let headerChromeView = ConversationHeaderChromeView()
    let stepTitleLabel = ThemeLabel(font: .regular, textColor: .white)
    let progressView = ConversationProgressSegmentsView(segmentCount: 5)
    let composerView = ConversationComposerShellView()
    let timelineStore = OnboardingConversationTimelineStore()

    private(set) var guidePerson: PersonType?
    private(set) var guideDisplayName: String = "Jibber"
    private var preserveTimelineFocusOnNextUpdate = false
    private var timelineFocusGeneration = 0
    private var isComposerBusy = false
    private weak var hostedContentView: UIView?
#if !APPCLIP
    private var parseTimelineProvider: OnboardingParseConversationTimelineProvider?
#endif

    private lazy var timelineViewController: ConversationTimelineViewController = {
        let configuration = ConversationTimeMachineConfiguration(
            itemHeight: MessageContentView.bubbleHeight,
            stackDepth: 3,
            scalingKeyPoints: [1, 0.84, 0.65, 0.4],
            spacingKeyPoints: [0, 8, 14, 16],
            alphaKeyPoints: [1, 1, 0.75, 0],
            topOfStackY: 0
        )
        let controller = ConversationTimelineViewController(
            provider: self.timelineStore,
            configuration: configuration,
            capabilities: .onboarding
        ) { [weak self] collectionView, indexPath, entry, capabilities in
            guard let self,
                  let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: Self.timelineCellReuseIdentifier,
                    for: indexPath
                  ) as? OnboardingConversationMessageCell else {
                return UICollectionViewCell()
            }
            cell.configure(with: entry, capabilities: capabilities)
            return cell
        }
        controller.didScrollToPosition = { [weak self] position in
            guard let self else { return }
            self.progressView.set(
                progress: self.timelineProgress(at: position),
                animated: false
            )
        }
        controller.didSettleOnEntry = { [weak self] entry in
            guard let self,
                  !self.isComposerBusy,
                  let step = self.timelineStore.step(for: entry),
                  step != self.getCurrentStepID() else { return }
            self.preserveTimelineFocusOnNextUpdate = true
            self.didSelectTimelineStep(step)
        }
        return controller
    }()

    override func initializeViews() {
        super.initializeViews()

        self.view.set(backgroundColor: .B0)
        self.view.addSubview(self.headerChromeView)
        self.headerChromeView.centeredContentView.addSubview(self.stepTitleLabel)
        self.headerChromeView.centeredContentView.addSubview(self.progressView)
        self.stepTitleLabel.textAlignment = .center
        self.stepTitleLabel.adjustsFontSizeToFitWidth = true
        self.stepTitleLabel.minimumScaleFactor = 0.8

        self.addChild(viewController: self.timelineViewController, toView: self.view)
        self.timelineViewController.collectionView.register(
            OnboardingConversationMessageCell.self,
            forCellWithReuseIdentifier: Self.timelineCellReuseIdentifier
        )

        self.view.addSubview(self.composerView)
        self.composerView.onSwipeUpCommit = { [weak self] in
            guard let self else { return false }
            return await self.commitPrimaryAction()
        }
        self.composerView.onSwipeDownCommit = { [weak self] in
            guard let self else { return false }
            return await self.commitComposerSwipeDown()
        }

        // Phone, OTP, name, and manual-invite inputs autofocus. Keep the shared
        // composer bubble attached to the keyboard while preserving the current
        // Time Machine snap point.
        KeyboardManager.shared.$cachedKeyboardEndFrame
            .removeDuplicates()
            .mainSink { [weak self] _ in
                guard let self else { return }
                self.view.setNeedsLayout()
                UIView.animate(
                    withDuration: Theme.animationDurationFast,
                    delay: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction]
                ) {
                    self.view.layoutIfNeeded()
                } completion: { [weak self] _ in
                    self?.restoreCurrentTimelineSnapAfterKeyboardLayout()
                }
            }.store(in: &self.cancellables)

        self.updateUI(animateTyping: false)
    }

    func updateUI(animateTyping: Bool = true) {
        let step = self.getCurrentStepID()
        if let prompt = self.getMessage().map(localized),
           !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.timelineStore.upsertLocalPrompt(
                step: step,
                text: prompt,
                revision: self.getMessagingRevision()
            )
        }
#if !APPCLIP
        self.parseTimelineProvider?.updateTemporaryEntries(
            self.timelineStore.timelineEntries
        )
#endif

        let shouldPreserveTimelineFocus = self.preserveTimelineFocusOnNextUpdate
        self.preserveTimelineFocusOnNextUpdate = false
        let entries = self.timelineViewController.provider.timelineEntries
        let currentStepIndex = entries.lastIndex {
            self.timelineStore.step(for: $0) == step
        }
        let focusIndex = currentStepIndex ?? (entries.count - 1)
        let focusEntryID = entries.indices.contains(focusIndex)
            ? entries[focusIndex].id
            : nil
        self.timelineFocusGeneration &+= 1
        let focusGeneration = self.timelineFocusGeneration

        self.composerView.configure(mode: self.getComposerMode())
        self.composerView.setContextText(
            self.getContextIndicatorText(),
            animated: animateTyping
        )
        self.composerView.setSwipeAccessibilityActions(
            up: self.getSwipeUpAccessibilityName(),
            down: self.getSwipeDownAccessibilityName()
        )
        self.applyComposerControlState()

        let progress = self.getProgress()
        self.progressView.set(progress: progress, animated: animateTyping)
        self.progressView.setSettledStep(
            self.getCurrentStepID().timelineOrdinal + 1,
            announce: false
        )
        self.stepTitleLabel.text = self.getStepTitle()
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()

        self.timelineViewController.reloadTimeline(
            animatingDifferences: animateTyping
        ) { [weak self] in
            guard let self,
                  self.timelineFocusGeneration == focusGeneration,
                  self.getCurrentStepID() == step,
                  !shouldPreserveTimelineFocus,
                  let focusEntryID else { return }
            let collectionView = self.timelineViewController.collectionView
            guard !collectionView.isDragging,
                  !collectionView.isTracking,
                  !collectionView.isDecelerating,
                  let resolvedIndex = self.timelineViewController
                    .appliedIndex(forEntryID: focusEntryID) else { return }
            // Commit both the composer geometry and diffable content size
            // before selecting the Time Machine snap point. Otherwise a mode
            // height change can leave the final card enlarged and cropped.
            self.view.layoutIfNeeded()
            collectionView.layoutIfNeeded()
            collectionView.focus(
                itemAt: resolvedIndex,
                animated: animateTyping
            )
        }
    }

    func setGuide(
        person: PersonType?,
        displayName: String?,
        guideUserId: String? = nil,
        conversationId: String? = nil,
        messagingRevision: Int? = nil
    ) {
        self.guidePerson = person
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.guideDisplayName = trimmedName?.isEmpty == false ? trimmedName! : "Jibber"
        self.timelineStore.configureGuide(
            person,
            guideUserId: guideUserId,
            conversationId: conversationId,
            messagingRevision: messagingRevision
        )
#if !APPCLIP
        if User.current() != nil,
           let conversationId,
           !conversationId.isEmpty {
            self.rebindToCanonicalConversation(conversationId: conversationId)
        }
#endif
        self.updateUI(animateTyping: false)
    }

    func reconcileConversation(_ response: OnboardingConversationSyncResponse) {
        self.timelineStore.reconcile(with: response.turns, session: response.session)
#if !APPCLIP
        if let conversationId = response.session.conversationId,
           !conversationId.isEmpty {
            self.rebindToCanonicalConversation(conversationId: conversationId)
            self.parseTimelineProvider?.updateTemporaryEntries(
                self.timelineStore.timelineEntries
            )
            Task { [weak self] in
                await self?.parseTimelineProvider?.synchronize()
            }
        }
#endif
        self.reloadTimelineRestoringCurrentStep(animatingDifferences: false)
        self.view.setNeedsLayout()
    }

#if !APPCLIP
    /// Switches the already-visible Time Machine rail to the production Parse
    /// conversation controller. Stable client message IDs preserve the visible
    /// pre-auth cells until their authoritative Parse snapshots arrive.
    private func rebindToCanonicalConversation(conversationId: String) {
        if let parseTimelineProvider,
           parseTimelineProvider.conversationController.conversationId == conversationId {
            parseTimelineProvider.updateTemporaryEntries(
                self.timelineStore.timelineEntries
            )
            return
        }

        let provider = OnboardingParseConversationTimelineProvider(
            conversationId: conversationId,
            temporaryEntries: self.timelineStore.timelineEntries
        )
        provider.didChange = { [weak self, weak provider] in
            guard let self,
                  self.parseTimelineProvider === provider else { return }
            self.reloadTimelineRestoringCurrentStep(animatingDifferences: true)
        }
        self.parseTimelineProvider = provider
        self.invalidatePendingTimelineFocus()
        self.timelineViewController.provider = provider
        self.reloadTimelineRestoringCurrentStep(animatingDifferences: false)
    }
#endif

    private func invalidatePendingTimelineFocus() {
        self.timelineFocusGeneration &+= 1
    }

    /// A provider refresh invalidates any in-flight step transition, then
    /// replaces it with a newly guarded focus request for the current composer
    /// context. This keeps the rail and composer on the same prompt when Parse
    /// reconciles while a diffable snapshot is still applying.
    private func reloadTimelineRestoringCurrentStep(
        animatingDifferences: Bool
    ) {
        let step = self.getCurrentStepID()
        let focusEntryID = self.timelineViewController.provider.timelineEntries
            .last(where: { self.timelineStore.step(for: $0) == step })?
            .id
        self.invalidatePendingTimelineFocus()
        let focusGeneration = self.timelineFocusGeneration

        self.timelineViewController.reloadTimeline(
            animatingDifferences: animatingDifferences
        ) { [weak self] in
            guard let self,
                  self.timelineFocusGeneration == focusGeneration,
                  self.getCurrentStepID() == step,
                  let focusEntryID else { return }
            let collectionView = self.timelineViewController.collectionView
            guard !collectionView.isDragging,
                  !collectionView.isTracking,
                  !collectionView.isDecelerating,
                  let resolvedIndex = self.timelineViewController
                    .appliedIndex(forEntryID: focusEntryID) else { return }
            self.view.layoutIfNeeded()
            collectionView.layoutIfNeeded()
            collectionView.focus(
                itemAt: resolvedIndex,
                animated: animatingDifferences
            )
        }
    }

    private func timelineProgress(at continuousPosition: CGFloat) -> CGFloat {
        let entries = self.timelineViewController.provider.timelineEntries
        guard !entries.isEmpty else { return 1 }

        let clampedPosition = clamp(
            continuousPosition,
            0,
            CGFloat(max(0, entries.count - 1))
        )
        let lowerIndex = Int(floor(clampedPosition))
        let upperIndex = min(entries.count - 1, lowerIndex + 1)
        let fraction = clampedPosition - CGFloat(lowerIndex)
        let lower = CGFloat(entries[lowerIndex].progressOrdinal ?? 0)
        let upper = CGFloat(entries[upperIndex].progressOrdinal ?? Int(lower))
        let ordinal = lower + ((upper - lower) * fraction)
        return clamp(ordinal + 1, 1, 5)
    }

    func hostOnboardingContentView(_ view: UIView?) {
        self.hostedContentView = view
        self.composerView.host(view)
        self.view.setNeedsLayout()
    }

    func handleComposerRequestState(_ status: EventStatus) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if status == .loading {
                self.isComposerBusy = true
                self.applyComposerControlState()
                await self.composerView.handlePrimaryEvent(status)
                return
            }

            await self.composerView.handlePrimaryEvent(status)
            self.isComposerBusy = false
            self.applyComposerControlState()
        }
    }

    func refreshComposerSubmissionState() {
        self.applyComposerControlState()
        self.composerView.setSwipeAccessibilityActions(
            up: self.getSwipeUpAccessibilityName(),
            down: self.getSwipeDownAccessibilityName()
        )
    }

    private func applyComposerControlState() {
        self.timelineViewController.collectionView.isUserInteractionEnabled = !self.isComposerBusy
        self.composerView.setSwipeInteractionEnabled(!self.isComposerBusy)
        self.composerView.setSwipeSubmissionEnabled(
            !self.isComposerBusy && self.shouldEnablePrimaryAction(),
            for: .up
        )
        self.composerView.setSwipeSubmissionEnabled(
            !self.isComposerBusy && self.shouldEnableSwipeDownAction(),
            for: .down
        )
    }

    private func restoreCurrentTimelineSnapAfterKeyboardLayout() {
        let collectionView = self.timelineViewController.collectionView
        guard !collectionView.isDragging,
              !collectionView.isTracking,
              !collectionView.isDecelerating else { return }

        let currentStep = self.getCurrentStepID()
        let entries = self.timelineViewController.provider.timelineEntries
        guard let focusIndex = entries.lastIndex(where: {
            self.timelineStore.step(for: $0) == currentStep
        }) else { return }

        collectionView.layoutIfNeeded()
        collectionView.focus(itemAt: focusIndex, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let safeFrame = self.view.safeAreaLayoutGuide.layoutFrame
        let headerHeight: CGFloat = 54
        self.headerChromeView.frame = CGRect(
            x: Theme.ContentOffset.screenPadding.value,
            y: safeFrame.minY + Theme.ContentOffset.standard.value,
            width: self.view.width - Theme.ContentOffset.screenPadding.value.doubled,
            height: headerHeight
        )
        self.headerChromeView.layoutIfNeeded()

        self.stepTitleLabel.frame = CGRect(
            x: 0,
            y: 0,
            width: self.headerChromeView.centeredContentView.width,
            height: 24
        )
        self.progressView.frame = CGRect(
            x: 0,
            y: 32,
            width: self.headerChromeView.centeredContentView.width,
            height: 12
        )

        let keyboardFrame = KeyboardManager.shared.cachedKeyboardEndFrame
        let localKeyboardTop = self.view.convert(keyboardFrame, from: nil).minY
        let keyboardIsVisible = keyboardFrame.height > 0
            && localKeyboardTop < safeFrame.maxY
        let composerBottom = keyboardIsVisible
            ? max(safeFrame.minY, localKeyboardTop)
            : safeFrame.maxY
        let composerHeight = self.getComposerHeight()
        self.composerView.frame = CGRect(
            x: 0,
            y: max(self.headerChromeView.bottom, composerBottom - composerHeight),
            width: self.view.width,
            height: composerHeight
        )

        let timelineTop = self.headerChromeView.bottom + Theme.ContentOffset.standard.value
        self.timelineViewController.view.frame = CGRect(
            x: Theme.ContentOffset.xtraLong.value,
            y: timelineTop,
            width: max(
                1,
                self.view.width - Theme.ContentOffset.xtraLong.value.doubled
            ),
            height: max(1, self.composerView.top - timelineTop)
        )
    }

    // MARK: - Subclass contract

    func getMessage() -> Localized? { nil }
    func getCurrentStepID() -> OnboardingStepID { .welcome }
    func getComposerMode() -> ConversationComposerMode { .action }
    func getMessagingRevision() -> Int { 0 }
    func getProgress() -> CGFloat { 1 }
    func getStepTitle() -> String { "1. Welcome" }
    func getContextIndicatorText() -> String? { nil }
    func getSwipeUpAccessibilityName() -> String? { nil }
    func getSwipeDownAccessibilityName() -> String? { nil }
    func getComposerHeight() -> CGFloat { 112 }
    func shouldEnablePrimaryAction() -> Bool { true }
    func shouldEnableSwipeDownAction() -> Bool { false }
    func didSelectPrimaryAction() {}
    func didSelectComposerSwipeDown() {}
    func commitPrimaryAction() async -> Bool {
        self.didSelectPrimaryAction()
        return true
    }
    func commitComposerSwipeDown() async -> Bool {
        self.didSelectComposerSwipeDown()
        return true
    }
    func didSelectTimelineStep(_ step: OnboardingStepID) {}
}
