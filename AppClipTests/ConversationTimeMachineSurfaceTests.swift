//
//  ConversationTimeMachineSurfaceTests.swift
//  AppClipTests
//

import XCTest
import Combine
import PhoneNumberKit
import Localization
@testable import AppClip

@MainActor
final class ConversationTimeMachineSurfaceTests: XCTestCase {

    func testCanonicalRestoreSuppressesRetainedLaunchActivity() {
        XCTAssertFalse(
            OnboardingLaunchActivityDispatchPolicy.shouldDispatch(
                isRestoringCanonicalOnboarding: true,
                isPreview: false
            )
        )
        XCTAssertFalse(
            OnboardingLaunchActivityDispatchPolicy.shouldDispatch(
                isRestoringCanonicalOnboarding: false,
                isPreview: true
            )
        )
        XCTAssertTrue(
            OnboardingLaunchActivityDispatchPolicy.shouldDispatch(
                isRestoringCanonicalOnboarding: false,
                isPreview: false
            )
        )
    }

    func testTimelineRefreshAppliesSameIDTemporaryContentChanges() {
        let ids = ["onboarding:7:phone:prompt"]

        XCTAssertTrue(
            ConversationTimelineRefreshPolicy.shouldApply(
                currentIDs: ids,
                nextIDs: ids,
                containsPersistedEntries: false,
                forcesContentRefresh: true
            )
        )
        XCTAssertFalse(
            ConversationTimelineRefreshPolicy.shouldApply(
                currentIDs: ids,
                nextIDs: ids,
                containsPersistedEntries: false,
                forcesContentRefresh: false
            )
        )
    }

    func testLocalMessagePresentationRefreshesStableIdentityContent() {
        let message = OnboardingTimelineMessage(
            id: "onboarding:7:welcome:prompt",
            conversationId: "onboarding-preauth",
            createdAt: Date(timeIntervalSince1970: 7),
            isFromCurrentUser: false,
            authorId: "guide-1",
            text: "Welcome",
            person: nil,
            step: .welcome,
            revision: 7,
            automated: true
        )
        let cell = ConversationMessagePresentationCell(frame: .zero)

        XCTAssertTrue(cell.hasPresentationChanges(from: message, to: message))
    }

    func testCanonicalWelcomeRendersExactlyTwoChoices() throws {
        let controller = WelcomeViewController()
        controller.usesCanonicalEntryChoices = true
        controller.mode = .standard
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 358, height: 124)
        controller.view.layoutIfNeeded()

        let visibleChoices = controller.view.subviews.compactMap { view -> ThemeButton? in
            guard let button = view as? ThemeButton, !button.isHidden else { return nil }
            return button
        }

        XCTAssertEqual(visibleChoices.count, 2)
        XCTAssertEqual(
            try XCTUnwrap(controller.waitlistButton.attributedTitle(for: .normal)?.string),
            "Log in or sign up"
        )
        XCTAssertEqual(
            try XCTUnwrap(controller.rsvpButton.attributedTitle(for: .normal)?.string),
            "Enter invite code"
        )
        XCTAssertTrue(controller.inviteCodeTextField.isHidden)
        XCTAssertEqual(controller.canonicalEntryState, .choices)
    }

    func testCanonicalWelcomeAccountChoiceUsesAutomaticAccountPathCallback() {
        let controller = WelcomeViewController()
        controller.usesCanonicalEntryChoices = true
        controller.mode = .standard
        controller.loadViewIfNeeded()
        var selectedAccountPath = false
        controller.onDidComplete = { result in
            guard case .success(.waitlist) = result else { return }
            selectedAccountPath = true
        }

        controller.waitlistButton.sendActions(for: .touchUpInside)

        XCTAssertTrue(selectedAccountPath)
        XCTAssertEqual(controller.canonicalEntryState, .choices)
        XCTAssertTrue(controller.inviteCodeTextField.isHidden)
    }

    func testWelcomeInviteEntryReplacesChoicesInSameComposerAndCanReturn() {
        let controller = WelcomeViewController()
        controller.usesCanonicalEntryChoices = true
        controller.mode = .standard
        controller.loadViewIfNeeded()
        let originalView = controller.view

        controller.showInviteCodeEntry()

        XCTAssertTrue(controller.view === originalView)
        XCTAssertEqual(controller.canonicalEntryState, .inviteCode)
        XCTAssertTrue(controller.waitlistButton.isHidden)
        XCTAssertTrue(controller.rsvpButton.isHidden)
        XCTAssertFalse(controller.inviteCodeTextField.isHidden)
        XCTAssertEqual(
            controller.inviteCodeTextField.accessibilityCustomActions?.map(\.name),
            ["Back to options"]
        )

        XCTAssertTrue(controller.returnToChoices())
        XCTAssertTrue(controller.view === originalView)
        XCTAssertEqual(controller.canonicalEntryState, .choices)
        XCTAssertFalse(controller.waitlistButton.isHidden)
        XCTAssertFalse(controller.rsvpButton.isHidden)
        XCTAssertTrue(controller.inviteCodeTextField.isHidden)
        XCTAssertNil(controller.inviteCodeTextField.accessibilityCustomActions)
    }

    func testLockedWelcomeCannotReenterOrResolveManualInvitation() {
        let controller = WelcomeViewController()
        controller.usesCanonicalEntryChoices = true
        controller.mode = .standard
        controller.loadViewIfNeeded()
        var resolutionCount = 0
        controller.onResolveInviteCode = { _ in resolutionCount += 1 }

        controller.showInviteCodeEntry()
        controller.inviteCodeTextField.text = "reservation-1"
        controller.setCanonicalEntryLocked(true)

        XCTAssertEqual(controller.canonicalEntryState, .choices)
        XCTAssertEqual(controller.enteredInviteCode, "")
        XCTAssertTrue(controller.waitlistButton.isHidden)
        XCTAssertTrue(controller.rsvpButton.isHidden)
        XCTAssertTrue(controller.inviteCodeTextField.isHidden)

        controller.showInviteCodeEntry()
        controller.submitInviteCodeIfPossible()

        XCTAssertEqual(controller.canonicalEntryState, .choices)
        XCTAssertFalse(controller.returnToChoices())
        XCTAssertEqual(resolutionCount, 0)
    }

    func testOnboardingCapabilitiesExcludeMessagingAffordances() {
        XCTAssertTrue(ConversationCapabilities.onboarding.contains(.timestamps))
        XCTAssertFalse(ConversationCapabilities.onboarding.contains(.deliveryMetadata))
        XCTAssertFalse(ConversationCapabilities.onboarding.contains(.replies))
        XCTAssertFalse(ConversationCapabilities.onboarding.contains(.attachments))
        XCTAssertFalse(ConversationCapabilities.onboarding.contains(.contextMenus))
        XCTAssertTrue(ConversationCapabilities.production.contains(.replies))
        XCTAssertTrue(ConversationCapabilities.production.contains(.attachments))
        XCTAssertTrue(ConversationCapabilities.production.contains(.contextMenus))
        XCTAssertTrue(ConversationCapabilities.production.contains(.timestamps))
    }

    func testOnboardingMessageShowsTimestampWithoutDeliveryAffordances() throws {
        let createdAt = Date().addingTimeInterval(-3 * 60 * 60)
        let message = OnboardingTimelineMessage(
            id: "onboarding:1:phone:prompt",
            conversationId: "onboarding-preauth",
            createdAt: createdAt,
            isFromCurrentUser: false,
            authorId: "onboarding-guide",
            text: "What’s your phone number?",
            person: nil,
            step: .phone,
            revision: 1,
            automated: true
        )
        let cell = ConversationMessagePresentationCell(
            frame: CGRect(x: 0, y: 0, width: 358, height: MessageContentView.bubbleHeight)
        )
        cell.configure(
            with: ConversationTimelineEntry(message: message),
            capabilities: .onboarding
        )
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        XCTAssertFalse(cell.content.dateView.isHidden)
        XCTAssertEqual(
            try XCTUnwrap(cell.content.dateView.text),
            createdAt.getTimeAgo().string
        )
        XCTAssertTrue(cell.content.deliveryView.isHidden)
        XCTAssertEqual(
            cell.content.dateView.left,
            cell.content.authorView.right + MessageContentView.padding.value,
            accuracy: 0.001
        )
    }

    func testOnboardingTimelineUsesProductionConversationHorizontalPadding() throws {
        let controller = UserOnboardingViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let timelineController = try XCTUnwrap(
            controller.children.compactMap { $0 as? ConversationTimelineViewController }.first
        )
        XCTAssertEqual(
            timelineController.view.frame.minX,
            Theme.ContentOffset.xtraLong.value,
            accuracy: 0.001
        )
        XCTAssertEqual(
            timelineController.view.frame.width,
            controller.view.width - Theme.ContentOffset.xtraLong.value.doubled,
            accuracy: 0.001
        )
    }

    func testSharedComposerShellAppliesModeAndCapabilityPolicy() {
        let bubbleView = SpeechBubbleView(orientation: .up, bubbleColor: .B1)
        let attachmentView = UIView()
        let expressionView = UIView()
        let typingIndicatorView = UIView()
        let unreadControlView = UIView()
        let shell = ConversationComposerShell(
            bubbleView: bubbleView,
            attachmentView: attachmentView,
            expressionView: expressionView,
            typingIndicatorView: typingIndicatorView,
            unreadControlView: unreadControlView,
            configuration: .productionChat
        )

        XCTAssertEqual(shell.mode, .chat)
        XCTAssertTrue(shell.supports(.attachments))
        XCTAssertTrue(attachmentView.isVisible)
        XCTAssertTrue(expressionView.isVisible)
        XCTAssertTrue(typingIndicatorView.isVisible)
        XCTAssertTrue(unreadControlView.isVisible)

        shell.configure(
            .onboarding(mode: .faceCapture, showsBack: true, showsPrimary: true)
        )

        XCTAssertEqual(shell.mode, .faceCapture)
        XCTAssertFalse(shell.supports(.attachments))
        XCTAssertFalse(attachmentView.isVisible)
        XCTAssertFalse(expressionView.isVisible)
        XCTAssertFalse(typingIndicatorView.isVisible)
        XCTAssertFalse(unreadControlView.isVisible)
    }

    func testSharedComposerAlignsBackAndPrimaryControlCenters() {
        let composerView = ConversationComposerShellView()
        composerView.frame = CGRect(x: 0, y: 0, width: 390, height: 112)
        composerView.configure(
            mode: .phone,
            primaryTitle: "Continue",
            showsBack: true,
            showsPrimary: true
        )
        composerView.layoutIfNeeded()

        let primaryCenterInComposer = composerView.bubbleView.frame.minY
            + composerView.primaryButton.center.y
        XCTAssertEqual(
            composerView.backButton.center.y,
            primaryCenterInComposer,
            accuracy: 0.001
        )
    }

    func testCanonicalComposerModesDoNotRenderLegacyControls() {
        let composerView = ConversationComposerShellView()
        let modes: [ConversationComposerMode] = [
            .welcomeChoices,
            .inviteCode,
            .phone,
            .verificationCode,
            .name,
            .faceCapture
        ]

        for mode in modes {
            composerView.configure(mode: mode)

            XCTAssertTrue(composerView.backButton.isHidden, "Back visible for \(mode)")
            XCTAssertTrue(composerView.primaryButton.isHidden, "Primary visible for \(mode)")
            XCTAssertNil(composerView.primaryButton.accessibilityIdentifier)
        }
    }

    func testContextIndicatorIsImmediatelyAboveComposerBubble() {
        let composerView = ConversationComposerShellView()
        composerView.frame = CGRect(x: 0, y: 0, width: 390, height: 112)
        composerView.configure(mode: .phone)
        composerView.setContextText("Mobile number", animated: false)
        composerView.layoutIfNeeded()

        XCTAssertEqual(composerView.contextIndicatorView.displayedText, "Mobile number")
        XCTAssertFalse(composerView.contextIndicatorView.isHidden)
        XCTAssertLessThanOrEqual(
            composerView.contextIndicatorView.frame.maxY,
            composerView.bubbleView.frame.minY
        )
        XCTAssertEqual(
            composerView.bubbleView.frame.minY
                - composerView.contextIndicatorView.frame.maxY,
            4,
            accuracy: 0.001
        )
    }

    func testConversationTextEntryStyleRemovesUnderlineAndLocalShadow() throws {
        let textField = TextField()
        let entryField = TextEntryField(
            with: textField,
            placeholder: nil,
            style: .conversationComposer
        )
        entryField.frame = CGRect(x: 0, y: 0, width: 320, height: 56)
        entryField.layoutIfNeeded()

        let decorationViews = entryField.subviews.filter { $0 !== textField }
        XCTAssertEqual(decorationViews.count, 1)
        XCTAssertTrue(try XCTUnwrap(decorationViews.first).isHidden)
        XCTAssertEqual(entryField.layer.shadowOpacity, 0)
    }

    func testVerificationComposerUsesNumericOneTimeCodeInput() {
        let controller = CodeViewController()
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.textField.keyboardType, .numberPad)
        XCTAssertEqual(controller.textField.textContentType, .oneTimeCode)
        XCTAssertTrue(controller.validate(text: "0123"))
        XCTAssertTrue(controller.validate(text: "0 1 2 3"))
        XCTAssertFalse(controller.validate(text: "ABCD"))
        XCTAssertFalse(controller.validate(text: "12345"))
    }

    func testNameValidationPublishesOnlyStateTransitionsAndPureValidityDoesNotMutate() {
        let controller = NameViewController()
        var publishedStates: [NameViewController.State] = []
        let cancellable = controller.$state
            .dropFirst()
            .sink { publishedStates.append($0) }

        XCTAssertFalse(controller.validate(text: "Benjamin"))
        XCTAssertEqual(controller.state, .givenNameValid)
        XCTAssertEqual(publishedStates, [.givenNameValid])

        XCTAssertFalse(controller.validate(text: "Benjamin"))
        XCTAssertEqual(
            publishedStates,
            [.givenNameValid],
            "Revalidating unchanged input must not enqueue another UI update"
        )

        XCTAssertTrue(controller.isSubmissionValid("Benjamin Dodgson"))
        XCTAssertFalse(controller.isSubmissionValid("Benjamin"))
        XCTAssertEqual(controller.state, .givenNameValid)
        XCTAssertEqual(publishedStates, [.givenNameValid])

        withExtendedLifetime(cancellable) {}
    }

    func testFaceCaptureComposerReservesFullWidthContentAboveControls() {
        let composerView = ConversationComposerShellView()
        let hostedView = UIView()
        composerView.frame = CGRect(x: 0, y: 0, width: 390, height: 420)
        composerView.configure(
            mode: .faceCapture,
            primaryTitle: "Capture",
            showsBack: true,
            showsPrimary: true
        )
        composerView.host(hostedView)
        composerView.layoutIfNeeded()

        XCTAssertGreaterThan(composerView.contentView.width, 250)
        XCTAssertLessThanOrEqual(
            composerView.contentView.bottom,
            composerView.primaryButton.top - Theme.ContentOffset.short.value
        )
        XCTAssertEqual(hostedView.frame, composerView.contentView.bounds)
    }

    func testEmbeddedFaceCaptureLeavesGuidanceToExternalContextIndicator() {
        let controller = FaceCaptureViewController()
        controller.usesEmbeddedCaptureLayout = true
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 430, height: 290)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        XCTAssertTrue(controller.label.isHidden)
        XCTAssertGreaterThan(controller.cameraViewContainer.height, 0)
        XCTAssertLessThanOrEqual(
            controller.cameraViewContainer.bottom,
            controller.view.safeAreaLayoutGuide.layoutFrame.maxY
        )
    }

    func testCapturedFaceStateShowsUsePhotoHidesCaptureAndRetakesFromPreview() async throws {
        let controller = ProfilePhotoCaptureViewController()
        controller.faceCaptureVC = TestFaceCaptureViewController()
        controller.usesEmbeddedComposer = true
        controller.loadViewIfNeeded()
        let preview = try XCTUnwrap(
            controller.view.subviews.compactMap { $0 as? DisplayableImageView }.first
        )
        let imageReady = self.expectation(description: "captured photo is rendered")
        let imageStateCancellable = preview.$state
            .dropFirst()
            .sink { state in
                if case .success = state {
                    imageReady.fulfill()
                }
            }
        preview.displayable = UIImage()
        await self.fulfillment(of: [imageReady], timeout: 1)
        controller.currentState = .review
        await Task.yield()
        await Task.yield()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 420)
        controller.view.layoutIfNeeded()

        guard case .review = controller.currentState else {
            XCTFail("Expected captured fixture to enter review")
            return
        }
        XCTAssertTrue(controller.hasCapturedPhoto)
        XCTAssertTrue(controller.canSubmitCapturedPhoto)
        XCTAssertEqual(controller.primaryActionTitle, "Use this photo")
        XCTAssertEqual(controller.contextText, "Use this photo")

        let captureButton = try XCTUnwrap(
            controller.view.subviews.compactMap { $0 as? ThemeButton }.first
        )
        XCTAssertTrue(captureButton.isHidden)

        let retakeRecognizer = try XCTUnwrap(preview.tapRecognizer)
        _ = (retakeRecognizer as NSObject).perform(NSSelectorFromString("execute"))
        await Task.yield()
        await Task.yield()

        // The post-retake camera state depends on simulator authorization
        // (`renderFaceImage`, scanning, or an unavailable-camera state). The
        // invariant is that the accepted still is discarded and Capture/Open
        // Settings replaces the review submission state.
        XCTAssertFalse(controller.hasCapturedPhoto)
        XCTAssertFalse(controller.canSubmitCapturedPhoto)
        XCTAssertNotEqual(controller.primaryActionTitle, "Use this photo")
        XCTAssertNotEqual(controller.contextText, "Use this photo")
        XCTAssertFalse(captureButton.isHidden)

        withExtendedLifetime(imageStateCancellable) {}
    }

    func testMessagePromptShrinksBeforeSingleLineTruncation() {
        let textView = MessageTextView(font: .regular, textColor: .white)
        textView.frame = CGRect(x: 0, y: 0, width: 276, height: 120)
        textView.text = "What’s your full name?"

        textView.updateFontSize(state: .expanded)

        XCTAssertEqual(textView.font?.pointSize, FontType.medium.size)
    }

    func testExplicitlyMultilineMessageDoesNotUseOversizedPromptFont() {
        let textView = MessageTextView(font: .regular, textColor: .white)
        textView.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        textView.text = "Hi\nthere"

        textView.updateFontSize(state: .expanded)

        XCTAssertEqual(textView.font?.pointSize, FontType.regular.size)
    }

    func testContinuousPositionAndSnappingUseInjectedItemHeight() {
        let layout = ConversationTimeMachineCollectionViewLayout(itemHeight: 100)
        let collectionView = ConversationTimeMachineCollectionView(layout: layout)
        let fixture = TimelineFixture(itemCount: 4)
        layout.dataSource = fixture
        collectionView.dataSource = fixture
        collectionView.register(
            UICollectionViewCell.self,
            forCellWithReuseIdentifier: TimelineFixture.reuseIdentifier
        )
        collectionView.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        collectionView.contentOffset = CGPoint(x: 0, y: 150)

        XCTAssertEqual(layout.continuousFocusedPosition, 1.5, accuracy: 0.001)
        XCTAssertEqual(
            layout.targetContentOffset(
                forProposedContentOffset: CGPoint(x: 0, y: 149),
                withScrollingVelocity: .zero
            ).y,
            100,
            accuracy: 0.001
        )

        layout.itemHeight = 80
        XCTAssertEqual(layout.continuousFocusedPosition, 1.875, accuracy: 0.001)
    }

    func testOnboardingProgressInterpolatesFromTimelinePosition() {
        let store = OnboardingConversationTimelineStore()
        store.upsertLocalPrompt(step: .welcome, text: "Welcome", revision: 9)
        store.upsertLocalPrompt(step: .phone, text: "Phone", revision: 9)
        store.upsertLocalPrompt(step: .verification, text: "Code", revision: 9)
        store.upsertLocalPrompt(step: .name, text: "Name", revision: 9)
        store.upsertLocalPrompt(step: .faceCapture, text: "Photo", revision: 9)

        XCTAssertEqual(store.progress(at: -10), 1, accuracy: 0.001)
        XCTAssertEqual(store.progress(at: 0), 1, accuracy: 0.001)
        XCTAssertEqual(store.progress(at: 1), 2, accuracy: 0.001)
        XCTAssertEqual(store.progress(at: 1.5), 2.5, accuracy: 0.001)
        XCTAssertEqual(store.progress(at: 2), 3, accuracy: 0.001)
        XCTAssertEqual(store.progress(at: 3), 4, accuracy: 0.001)
        XCTAssertEqual(store.progress(at: 4), 5, accuracy: 0.001)
        XCTAssertEqual(store.progress(at: 100), 5, accuracy: 0.001)
    }

    func testFiveSegmentProgressNeverExposesZeroAndSettlesAccessibilitySeparately() {
        let progressView = ConversationProgressSegmentsView(segmentCount: 5)
        progressView.frame = CGRect(x: 0, y: 0, width: 300, height: 12)

        XCTAssertEqual(progressView.segmentCount, 5)
        XCTAssertEqual(progressView.subviews.count, 5)
        XCTAssertEqual(progressView.progress, 1)
        XCTAssertEqual(progressView.accessibilityValue, "Step 1 of 5")

        progressView.set(progress: 0, animated: false)
        XCTAssertEqual(progressView.progress, 1)
        XCTAssertEqual(progressView.accessibilityValue, "Step 1 of 5")

        progressView.set(progress: 3.75, animated: false)
        XCTAssertEqual(progressView.progress, 3.75, accuracy: 0.001)
        XCTAssertEqual(
            progressView.accessibilityValue,
            "Step 1 of 5",
            "Continuous scrolling must not announce an unsettled step"
        )

        progressView.setSettledStep(4)
        XCTAssertEqual(progressView.settledStep, 4)
        XCTAssertEqual(progressView.accessibilityValue, "Step 4 of 5")

        progressView.setSettledStep(0)
        XCTAssertEqual(progressView.settledStep, 1)
        XCTAssertEqual(progressView.accessibilityValue, "Step 1 of 5")
    }

    func testSharedSwipeSubmissionRejectsInvalidBeginAndFailedCommitCancels() async {
        let host = UIView()
        let controller = ConversationVerticalSwipeSubmissionController(attachingTo: host)
        var cancelledDirections: [ConversationVerticalSwipeDirection] = []

        controller.canBegin = { $0 == .up }
        controller.commit = { _ in false }
        controller.didCancel = { cancelledDirections.append($0) }

        XCTAssertFalse(controller.submit(.down))
        XCTAssertTrue(controller.submit(.up))

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(cancelledDirections, [.up])
        XCTAssertFalse(controller.isCommitting)
    }

    func testSharedSwipeSubmissionPreventsDuplicateCommitFlights() async {
        let host = UIView()
        let controller = ConversationVerticalSwipeSubmissionController(attachingTo: host)
        var commitCount = 0

        controller.commit = { _ in
            commitCount += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
            return true
        }

        XCTAssertTrue(controller.submit(.up))
        XCTAssertTrue(controller.isCommitting)
        XCTAssertFalse(controller.submit(.up))

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(commitCount, 1)
        XCTAssertFalse(controller.isCommitting)
    }

    func testPhysicalShortSwipeCancelsWithoutMutatingDraft() async {
        let host = UIView()
        let pan = TestPanGestureRecognizer()
        let controller = ConversationVerticalSwipeSubmissionController(
            attachingTo: host,
            panGestureRecognizer: pan,
            commitDistance: 96
        )
        var draft = "unchanged invite code"
        var commitCount = 0
        var cancelledDirections: [ConversationVerticalSwipeDirection] = []
        controller.commit = { _ in
            commitCount += 1
            draft = "submitted"
            return true
        }
        controller.didCancel = { cancelledDirections.append($0) }

        pan.testVelocity = CGPoint(x: 0, y: -200)
        pan.testTranslation = CGPoint(x: 0, y: -20)
        XCTAssertTrue(controller.gestureRecognizerShouldBegin(pan))
        controller.handleTestPan(pan, state: .began)
        pan.testTranslation = CGPoint(x: 0, y: -40)
        controller.handleTestPan(pan, state: .ended)

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(draft, "unchanged invite code")
        XCTAssertEqual(cancelledDirections, [.up])
    }

    func testPhysicalSwipeRejectsHorizontalIntentAndSupportsStationaryProductionBegin() {
        let host = UIView()
        let pan = TestPanGestureRecognizer()
        let controller = ConversationVerticalSwipeSubmissionController(
            attachingTo: host,
            panGestureRecognizer: pan
        )
        controller.commit = { _ in true }

        pan.testVelocity = CGPoint(x: 200, y: -20)
        XCTAssertFalse(controller.gestureRecognizerShouldBegin(pan))

        pan.testVelocity = .zero
        XCTAssertFalse(controller.gestureRecognizerShouldBegin(pan))
        controller.allowsStationaryBegin = true
        XCTAssertTrue(controller.gestureRecognizerShouldBegin(pan))
    }

    func testComposerEnablesSwipeDirectionsIndependentlyAndPreservesRejectedDraft() async throws {
        let composer = ConversationComposerShellView()
        var draft = "2015550123"
        var upCommitCount = 0
        var downCommitCount = 0
        composer.onSwipeUp = {
            upCommitCount += 1
            draft = ""
        }
        composer.onSwipeDown = { downCommitCount += 1 }
        composer.setSwipeSubmissionEnabled(false, for: .up)
        composer.setSwipeSubmissionEnabled(true, for: .down)
        composer.setSwipeAccessibilityActions(up: "Submit", down: "Back to options")

        let actions = try XCTUnwrap(composer.accessibilityCustomActions)
        XCTAssertEqual(actions.map(\.name), ["Submit", "Back to options"])
        self.performAccessibilityAction(actions[0])
        self.performAccessibilityAction(actions[1])

        await Task.yield()
        await Task.yield()

        XCTAssertEqual(upCommitCount, 0)
        XCTAssertEqual(downCommitCount, 1)
        XCTAssertEqual(draft, "2015550123")

        composer.setSwipeSubmissionEnabled(true, for: .up)
        self.performAccessibilityAction(actions[0])
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(upCommitCount, 1)
        XCTAssertEqual(draft, "")
    }

    func testComposerAsyncSwipeCommitKeepsSingleFlightGateUntilCompletion() async throws {
        let composer = ConversationComposerShellView()
        var commitCount = 0
        composer.onSwipeUpCommit = {
            commitCount += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
            return true
        }
        composer.setSwipeSubmissionEnabled(true, for: .up)
        composer.setSwipeAccessibilityActions(up: "Submit")

        let action = try XCTUnwrap(composer.accessibilityCustomActions?.first)
        self.performAccessibilityAction(action)
        self.performAccessibilityAction(action)
        await Task.yield()

        XCTAssertEqual(commitCount, 1)

        try? await Task.sleep(nanoseconds: 100_000_000)
        self.performAccessibilityAction(action)
        await Task.yield()

        XCTAssertEqual(commitCount, 2)
    }

    func testPassContextUsesContextualWelcomeAtStepOneWithoutGenericChoices() {
        let delegate = OnboardingDelegateSpy()
        let controller = OnboardingViewController(with: delegate)
        controller.loadViewIfNeeded()
        controller.passId = "pass-1"
        controller.welcomeVC.mode = .pass
        controller.switchTo(.welcome(controller.welcomeVC))
        controller.updateUI(animateTyping: false)

        XCTAssertEqual(controller.getCurrentStepID(), .welcome)
        XCTAssertEqual(controller.getProgress(), 1)
        XCTAssertEqual(controller.progressView.progress, 1)
        XCTAssertEqual(controller.progressView.accessibilityValue, "Step 1 of 5")
        XCTAssertEqual(controller.getComposerMode(), .action)
        XCTAssertTrue(controller.shouldEnablePrimaryAction())
        XCTAssertTrue(controller.welcomeVC.waitlistButton.isHidden)
        XCTAssertTrue(controller.welcomeVC.rsvpButton.isHidden)
        XCTAssertTrue(controller.welcomeVC.inviteCodeTextField.isHidden)
    }

    func testApplyingCanonicalSessionLocksManualInviteComposer() {
        let controller = OnboardingViewController(with: OnboardingDelegateSpy())
        controller.loadViewIfNeeded()
        controller.welcomeVC.usesCanonicalEntryChoices = true
        controller.welcomeVC.mode = .standard
        controller.welcomeVC.showInviteCodeEntry()
        controller.welcomeVC.inviteCodeTextField.text = "reservation-1"

        controller.applyCanonicalSession(
            OnboardingConversationSession(
                onboardingSessionId: "session-1",
                messagingRevision: OnboardingMessagingRepository.shared
                    .sessionSnapshot().revision,
                reachedStep: .welcome
            )
        )

        XCTAssertEqual(controller.canonicalSession?.onboardingSessionId, "session-1")
        XCTAssertTrue(controller.welcomeVC.isCanonicalEntryLocked)
        XCTAssertEqual(controller.welcomeVC.canonicalEntryState, .choices)
        XCTAssertEqual(controller.welcomeVC.enteredInviteCode, "")
        XCTAssertFalse(controller.shouldEnableSwipeDownAction())
        XCTAssertTrue(controller.welcomeVC.waitlistButton.isHidden)
        XCTAssertTrue(controller.welcomeVC.rsvpButton.isHidden)
        XCTAssertTrue(controller.welcomeVC.inviteCodeTextField.isHidden)
    }

    func testServerTurnsReconcileTemporaryPromptsByStableID() throws {
        let store = OnboardingConversationTimelineStore()
        store.upsertLocalPrompt(step: .phone, text: "Temporary phone prompt", revision: 7)
        XCTAssertEqual(store.timelineEntries.map(\.id), ["onboarding:7:phone:prompt"])

        let response = try OnboardingConversationSyncResponse(cloudValue: [
            "conversationId": "conversation-1",
            "guideUserId": "guide-1",
            "messagingRevision": 7,
            "reachedStep": "phone",
            "turns": [[
                "clientMessageId": "onboarding:7:phone:prompt",
                "authorId": "guide-1",
                "text": "Server phone prompt",
                "metadata": [
                    "onboarding": true,
                    "automated": true,
                    "onboardingStep": "phone",
                    "copyRevision": 7,
                    "suppressPush": true,
                    "suppressUnread": true,
                    "suppressBot": true
                ]
            ]]
        ])

        store.reconcile(with: response.turns, session: response.session)

        XCTAssertEqual(store.timelineEntries.count, 1)
        XCTAssertEqual(store.timelineEntries.first?.id, "onboarding:7:phone:prompt")
        XCTAssertEqual(store.conversationId, "conversation-1")
    }

    private func performAccessibilityAction(_ action: UIAccessibilityCustomAction) {
        if let handler = action.actionHandler {
            _ = handler(action)
            return
        }
        _ = (action.target as? NSObject)?.perform(action.selector)
    }
}

@MainActor
private final class TestPanGestureRecognizer: UIPanGestureRecognizer {
    var testVelocity = CGPoint.zero
    var testTranslation = CGPoint.zero

    override func velocity(in view: UIView?) -> CGPoint {
        self.testVelocity
    }

    override func translation(in view: UIView?) -> CGPoint {
        self.testTranslation
    }

}

@MainActor
private final class TestFaceCaptureViewController: FaceCaptureViewController {
    override func animate(text: Localized) {}
    override func beginSession() {}
}

@MainActor
private extension ConversationVerticalSwipeSubmissionController {
    func handleTestPan(
        _ pan: TestPanGestureRecognizer,
        state: UIGestureRecognizer.State
    ) {
        pan.setValue(state.rawValue, forKey: "state")
        _ = (self as NSObject).perform(
            NSSelectorFromString("handlePan:"),
            with: pan
        )
    }
}

@MainActor
private final class OnboardingDelegateSpy: OnboardingViewControllerDelegate {
    func onboardingViewControllerDidStartOnboarding(_ controller: OnboardingViewController) {}
    func onboardingViewControllerDidSelectRSVP(_ controller: OnboardingViewController) {}
    func onboardingViewControllerDidAcceptMomentInvitation(
        _ controller: OnboardingViewController
    ) {}
    func onboardingViewControllerDidDeferMomentInvitation(
        _ controller: OnboardingViewController
    ) {}
    func onboardingViewControllerDidResolveActiveInvitation(
        _ controller: OnboardingViewController,
        accepted: Bool
    ) {}
    func onboardingViewController(
        _ controller: OnboardingViewController,
        didEnter phoneNumber: PhoneNumber
    ) {}
    func onboardingViewControllerDidVerifyCode(
        _ controller: OnboardingViewController,
        andReturnCID conversationId: String?
    ) {}
    func onboardingViewController(
        _ controller: OnboardingViewController,
        didEnterName name: String
    ) {}
    func onboardingViewControllerDidTakePhoto(_ controller: OnboardingViewController) {}
}

@MainActor
private final class TimelineFixture: NSObject,
                                     UICollectionViewDataSource,
                                     TimeMachineCollectionViewLayoutDataSource {

    static let reuseIdentifier = "timeline-fixture"
    private let items: [FixtureItem]

    init(itemCount: Int) {
        self.items = (0..<itemCount).map { index in
            FixtureItem(
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                stableID: "fixture-\(index)"
            )
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        self.items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(
            withReuseIdentifier: Self.reuseIdentifier,
            for: indexPath
        )
    }

    func getTimeMachineItem(forItemAt indexPath: IndexPath) -> TimeMachineLayoutItemType {
        self.items[indexPath.item]
    }
}

private struct FixtureItem: TimeMachineLayoutItemType {
    let date: Date
    let stableID: String?
}
