import XCTest
@testable import AppClip

final class OnboardingMessagingTests: XCTestCase {
    func testBundledFallbackIsCompleteAndMatchesEmergencyCopy() throws {
        let document = try XCTUnwrap(
            OnboardingMessagingRepository.loadBundledFallback(
                from: Bundle(for: Config.self)
            )
        )

        try document.validate()
        XCTAssertEqual(document, .emergencyFallback)
        XCTAssertEqual(
            Set(document.locales["en", default: [:]].keys),
            Set(OnboardingMessageKey.allCases.map(\.rawValue))
        )
    }

    func testRejectsUnsupportedSchemaAndMissingRequiredCopy() {
        let unsupported = self.document(schemaVersion: 2)
        XCTAssertThrowsError(try unsupported.validate()) { error in
            XCTAssertEqual(
                error as? OnboardingMessagingValidationError,
                .unsupportedSchema(2)
            )
        }

        var messages = OnboardingMessagingDocument.emergencyFallback.locales["en"]!
        messages.removeValue(forKey: OnboardingMessageKey.photoCapture.rawValue)
        let incomplete = self.document(locales: ["en": messages])
        XCTAssertThrowsError(try incomplete.validate()) { error in
            XCTAssertEqual(
                error as? OnboardingMessagingValidationError,
                .missingMessage(locale: "en", key: OnboardingMessageKey.photoCapture.rawValue)
            )
        }
    }

    func testRejectsUnknownTokensAndNonPlainText() {
        var messages = OnboardingMessagingDocument.emergencyFallback.locales["en"]!
        messages[OnboardingMessageKey.phoneDefault.rawValue] = "Hello {{accountToken}}"
        XCTAssertThrowsError(try self.document(locales: ["en": messages]).validate())

        messages[OnboardingMessageKey.phoneDefault.rawValue] = "Read https://example.com"
        XCTAssertThrowsError(try self.document(locales: ["en": messages]).validate())
    }

    func testRejectsOversizedDocument() {
        let english = OnboardingMessagingDocument.emergencyFallback.locales["en"]!
        var locales = ["en": english]
        for localeIndex in 1..<20 {
            var messages = english
            for messageIndex in 0..<20 {
                messages["extra.\(messageIndex)"] = String(repeating: "x", count: 400)
            }
            locales["x-\(localeIndex)"] = messages
        }

        XCTAssertThrowsError(try self.document(locales: locales).validate()) { error in
            guard let validationError = error as? OnboardingMessagingValidationError,
                  case .documentTooLarge = validationError else {
                XCTFail("Expected documentTooLarge, received \(error)")
                return
            }
        }
    }

    func testLocaleFallbackAndAllowlistedReplacement() throws {
        let english = OnboardingMessagingDocument.emergencyFallback.locales["en"]!
        let spanish = [
            OnboardingMessageKey.guideSubtitle.rawValue: "Aquí para ayudarte",
            OnboardingMessageKey.welcomeInvitation.rawValue:
                "{{inviterName}} te invitó a conectar en Jibber."
        ]
        let document = self.document(locales: ["en": english, "es": spanish])
        let messaging = try OnboardingMessaging(
            document: document,
            source: .remote,
            preferredLanguages: ["es-MX"]
        )

        XCTAssertEqual(
            messaging.text(for: .welcomeInvitation, replacements: [.inviterName: "Maya"]),
            "Maya te invitó a conectar en Jibber."
        )
        XCTAssertEqual(messaging.text(for: .photoCapture), "Capture")
    }

    func testResolverRequiresMonotonicallyIncreasingRevision() throws {
        let fallback = self.document(revision: 0)
        let cached = self.document(revision: 3)
        let staleRemote = self.document(revision: 2)
        let newerRemote = self.document(revision: 4, guideUserId: "mayaUser")

        let staleResolution = try OnboardingMessagingResolver.resolve(
            remote: staleRemote,
            cached: cached,
            fallback: fallback
        )
        XCTAssertEqual(staleResolution.source, .cache)
        XCTAssertEqual(staleResolution.document.revision, 3)

        let newResolution = try OnboardingMessagingResolver.resolve(
            remote: newerRemote,
            cached: cached,
            fallback: fallback
        )
        XCTAssertEqual(newResolution.source, .remote)
        XCTAssertEqual(newResolution.document.guideUserId, "mayaUser")
    }

    func testResolverRejectsRevisionReuseWithChangedContent() throws {
        let fallback = self.document(revision: 0)
        let cached = self.document(revision: 3)
        var changedMessages = cached.locales["en"]!
        changedMessages[OnboardingMessageKey.guideSubtitle.rawValue] = "Changed without a revision"
        let changedRemote = self.document(revision: 3, locales: ["en": changedMessages])

        let resolution = try OnboardingMessagingResolver.resolve(
            remote: changedRemote,
            cached: cached,
            fallback: fallback
        )

        XCTAssertEqual(resolution.source, .cache)
        XCTAssertEqual(resolution.document, cached)
    }

    func testInvalidRemotePreservesLastKnownGood() throws {
        let fallback = self.document(revision: 0)
        let cached = self.document(revision: 2)
        let invalidRemote = self.document(schemaVersion: 99, revision: 3)

        let resolution = try OnboardingMessagingResolver.resolve(
            remote: invalidRemote,
            cached: cached,
            fallback: fallback
        )

        XCTAssertEqual(resolution.source, .cache)
        XCTAssertEqual(resolution.document, cached)
    }

    func testValidatedCacheRoundTrip() throws {
        let original = self.document(revision: 8, guideUserId: "guide_123")
        let decoded = try OnboardingMessagingDocument.decode(
            from: original.validatedData()
        )

        XCTAssertEqual(decoded, original)
    }

    @MainActor
    func testMessagingRevisionLookupReturnsExactSnapshotOrExplicitCallerFallback() {
        let repository = OnboardingMessagingRepository.shared
        let current = repository.sessionSnapshot()

        XCTAssertEqual(
            repository.sessionSnapshot(forRevision: current.revision)?.revision,
            current.revision
        )

        let missingRevision = Int.max
        XCTAssertNil(repository.sessionSnapshot(forRevision: missingRevision))
        let callerSelected = repository.sessionSnapshot(forRevision: missingRevision)
            ?? repository.sessionSnapshot()
        XCTAssertEqual(callerSelected.revision, current.revision)
    }

    @MainActor
    func testServerLockedDocumentInstallsOnFreshDeviceAndRejectsRevisionMismatch() throws {
        let repository = OnboardingMessagingRepository.shared
        let revision = repository.sessionSnapshot().revision + 10_000
        let document = self.document(
            revision: revision,
            conversation: .canonicalV1WithPresentation
        )
        let json = try XCTUnwrap(
            String(data: document.validatedData(), encoding: .utf8)
        )

        let installed = try XCTUnwrap(
            repository.sessionSnapshot(
                documentJSON: json,
                expectedRevision: revision
            )
        )
        XCTAssertEqual(installed.document, document)
        XCTAssertEqual(
            repository.sessionSnapshot(forRevision: revision)?.document,
            document
        )
        XCTAssertNil(
            repository.sessionSnapshot(
                documentJSON: json,
                expectedRevision: revision + 1
            )
        )
    }

    func testSessionSummaryDecodesLockedMessagingDocumentObject() throws {
        let document = self.document(
            revision: 47,
            conversation: .canonicalV1WithPresentation
        )
        let jsonObject = try JSONSerialization.jsonObject(
            with: document.validatedData()
        )
        let response = try OnboardingConversationSyncResponse(cloudValue: [
            "messagingRevision": 47,
            "messagingDocument": jsonObject,
            "turns": []
        ])
        let lockedJSON = try XCTUnwrap(response.session.messagingDocumentJSON)

        XCTAssertEqual(
            OnboardingMessagingRepository.decodeRemoteDocument(lockedJSON),
            document
        )
    }

    func testParseConfigAcceptsJSONStringAndLegacyObject() throws {
        let original = self.document(revision: 9, guideUserId: "maya-user")
        let data = try original.validatedData()
        let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8))
        let jsonObject = try JSONSerialization.jsonObject(with: data)

        XCTAssertEqual(
            OnboardingMessagingRepository.decodeRemoteDocument(jsonString),
            original
        )
        XCTAssertEqual(
            OnboardingMessagingRepository.decodeRemoteDocument(jsonObject),
            original
        )
        XCTAssertNil(OnboardingMessagingRepository.decodeRemoteDocument("not-json"))
    }

    func testLegacyV1DocumentWithoutConversationMetadataRemainsValid() throws {
        var legacyMessages = OnboardingMessagingDocument.emergencyFallback.locales["en"]!
        legacyMessages.removeValue(forKey: OnboardingMessageKey.automatedOnboardingLabel.rawValue)
        legacyMessages.removeValue(forKey: OnboardingMessageKey.aiGuideLabel.rawValue)
        legacyMessages.removeValue(forKey: OnboardingMessageKey.welcomeAction.rawValue)
        let legacy = self.document(locales: ["en": legacyMessages])

        try legacy.validate()
        let messaging = try OnboardingMessaging(
            document: legacy,
            source: .remote,
            preferredLanguages: ["en"]
        )

        XCTAssertEqual(messaging.conversationConfiguration, .canonicalV1)
        XCTAssertEqual(messaging.automatedPromptLabel, "Automated onboarding")
        XCTAssertEqual(messaging.aiGuideLabel, "AI guide")
        XCTAssertEqual(messaging.text(for: .welcomeAction), "Continue")
    }

    func testConversationConfigurationUsesStableStepsAndAllowlistedInputKinds() throws {
        let document = self.document(conversation: .canonicalV1)
        try document.validate()
        let messaging = try OnboardingMessaging(
            document: document,
            source: .remote,
            preferredLanguages: ["en-US"]
        )

        XCTAssertEqual(messaging.localeIdentifier, "en")
        XCTAssertEqual(messaging.inputKind(for: .welcome), .action)
        XCTAssertEqual(messaging.inputKind(for: .phone), .phone)
        XCTAssertEqual(messaging.inputKind(for: .verification), .verificationCode)
        XCTAssertEqual(messaging.inputKind(for: .name), .name)
        XCTAssertEqual(messaging.inputKind(for: .faceCapture), .faceCapture)
        XCTAssertEqual(messaging.inputKind(for: .completed), .chat)
        XCTAssertEqual(
            messaging.conversationConfiguration.steps.compactMap(\.progressIndex),
            [0, 1, 2, 3]
        )
    }

    func testPresentationConfigurationSuppliesFiveStepTitlesAndContexts() throws {
        let document = self.document(conversation: .canonicalV1WithPresentation)
        try document.validate()
        let messaging = try OnboardingMessaging(
            document: document,
            source: .remote,
            preferredLanguages: ["en-US"]
        )

        XCTAssertEqual(messaging.title(for: .welcome), "Welcome")
        XCTAssertEqual(messaging.title(for: .phone), "Phone")
        XCTAssertEqual(messaging.title(for: .verification), "Verification Code")
        XCTAssertEqual(messaging.title(for: .name), "Name")
        XCTAssertEqual(messaging.title(for: .faceCapture), "Face Capture")
        XCTAssertEqual(messaging.text(for: .welcomeAccountChoice), "Log in or sign up")
        XCTAssertEqual(messaging.text(for: .welcomeInviteChoice), "Enter invite code")
        XCTAssertEqual(messaging.text(for: .inviteContext), "Invite code")
        XCTAssertEqual(messaging.inputContext(for: .phone), "Mobile number")
        XCTAssertEqual(messaging.inputContext(for: .verification), "Code sent to %@")
        XCTAssertEqual(
            messaging.inputContext(for: .name, replacements: [.inviterName: "Maya"]),
            "How Maya will know you"
        )
        XCTAssertEqual(messaging.inputContext(for: .faceCapture), "Center your face")

        // Persisted V1 indices remain backwards compatible. Native timeline ordinals
        // are the authoritative five-step visual mapping.
        XCTAssertEqual(
            messaging.conversationConfiguration.steps.compactMap(\.progressIndex),
            [0, 1, 2, 3]
        )
    }

    func testLegacyConversationDocumentUsesNativePresentationFallbacks() throws {
        let document = self.document(conversation: .canonicalV1)
        let messaging = try OnboardingMessaging(
            document: document,
            source: .remote,
            preferredLanguages: ["en"]
        )

        XCTAssertEqual(messaging.title(for: .welcome), "Welcome")
        XCTAssertEqual(messaging.inputContext(for: .phone), "Mobile number")
        XCTAssertEqual(messaging.inputContext(for: .verification), "Code sent to %@")
    }

    func testPresentationConfigurationAllowsIndependentOptionalKeys() throws {
        var steps = OnboardingConversationMessagingConfiguration.canonicalV1.steps
        steps[0] = OnboardingMessagingStepDefinition(
            id: .welcome,
            inputKind: .action,
            progressIndex: nil,
            titleKey: .welcomeTitle
        )
        steps[1] = OnboardingMessagingStepDefinition(
            id: .phone,
            inputKind: .phone,
            progressIndex: 0,
            inputContextKey: .phoneContext
        )
        let configuration = OnboardingConversationMessagingConfiguration(
            version: OnboardingConversationMessagingConfiguration.supportedVersion,
            automatedPromptLabelKey: .automatedOnboardingLabel,
            aiGuideLabelKey: .aiGuideLabel,
            steps: steps
        )

        let document = self.document(conversation: configuration)
        try document.validate()
        let messaging = try OnboardingMessaging(
            document: document,
            source: .remote,
            preferredLanguages: ["en"]
        )

        XCTAssertEqual(messaging.title(for: .welcome), "Welcome")
        XCTAssertEqual(messaging.inputContext(for: .phone), "Mobile number")
        XCTAssertEqual(messaging.title(for: .phone), "Phone")
    }

    func testRejectsConversationConfigurationThatChangesNativeInputMapping() {
        var steps = OnboardingConversationMessagingConfiguration.canonicalV1.steps
        steps[1] = OnboardingMessagingStepDefinition(
            id: .phone,
            inputKind: .faceCapture,
            progressIndex: 0
        )
        let unsafe = OnboardingConversationMessagingConfiguration(
            version: 1,
            automatedPromptLabelKey: .automatedOnboardingLabel,
            aiGuideLabelKey: .aiGuideLabel,
            steps: steps
        )

        XCTAssertThrowsError(try self.document(conversation: unsafe).validate()) { error in
            guard let validationError = error as? OnboardingMessagingValidationError,
                  case .invalidConversationConfiguration = validationError else {
                XCTFail("Expected invalidConversationConfiguration, received \(error)")
                return
            }
        }
    }

    func testValidateCodeV2ResponseDecodesCanonicalSession() throws {
        let response = try OnboardingVerificationResponse(cloudValue: [
            "sessionToken": "session-token",
            "onboardingSessionId": "onboarding-1",
            "conversationId": "conversation-1",
            "guideUserId": "maya-user",
            "guideSource": "maya",
            "messagingRevision": 12,
            "reachedStep": "verification",
            "completed": false
        ])

        XCTAssertEqual(response.sessionToken, "session-token")
        XCTAssertEqual(response.session.onboardingSessionId, "onboarding-1")
        XCTAssertEqual(response.session.conversationId, "conversation-1")
        XCTAssertEqual(response.session.guideUserId, "maya-user")
        XCTAssertEqual(response.session.guideSource, .maya)
        XCTAssertEqual(response.session.messagingRevision, 12)
        XCTAssertEqual(response.session.reachedStep, .verification)
        XCTAssertFalse(response.session.completed)
        XCTAssertFalse(response.existingUser)
    }

    func testValidateCodeV2ResponseMarksCompletedExistingUser() throws {
        let response = try OnboardingVerificationResponse(cloudValue: [
            "sessionToken": "session-token",
            "conversationId": "conversation-1",
            "completed": true,
            "existingUser": true
        ])

        XCTAssertTrue(response.existingUser)
        XCTAssertTrue(response.session.completed)
        XCTAssertEqual(response.session.conversationId, "conversation-1")
    }

    func testValidateCodeV2ResponseRequiresOnlySessionToken() throws {
        let response = try OnboardingVerificationResponse(cloudValue: [
            "sessionToken": "session-token"
        ])

        XCTAssertNil(response.session.conversationId)
        XCTAssertNil(response.session.guideSource)
        XCTAssertNil(response.session.reachedStep)
        XCTAssertFalse(response.session.completed)

        XCTAssertThrowsError(
            try OnboardingVerificationResponse(cloudValue: ["conversationId": "conversation-1"])
        ) { error in
            XCTAssertEqual(
                error as? OnboardingCloudContractError,
                .missingField("sessionToken")
            )
        }
    }

    func testSyncResponseDecodesSafeTurnMetadataAndSkipsMalformedTurns() throws {
        let response = try OnboardingConversationSyncResponse(cloudValue: [
            "onboardingSessionId": "onboarding-1",
            "conversationId": "conversation-1",
            "guideSource": "configuredAgent",
            "reachedStep": "name",
            "turns": [
                [
                    "objectId": "message-1",
                    "clientMessageId": "onboarding:onboarding-1:name:prompt",
                    "authorId": "guide-1",
                    "text": "What’s your full name?",
                    "contentType": "text",
                    "createdAt": "2026-07-19T12:00:00.000Z",
                    "metadata": [
                        "onboarding": true,
                        "automated": true,
                        "onboardingStep": "name",
                        "copyRevision": 4,
                        "suppressPush": true,
                        "suppressUnread": true,
                        "suppressBot": true
                    ]
                ],
                ["text": "Missing a stable identifier"]
            ]
        ])

        XCTAssertEqual(response.session.guideSource, .configuredAgent)
        XCTAssertEqual(response.turns.count, 1)
        let turn = try XCTUnwrap(response.turns.first)
        XCTAssertEqual(turn.id, "onboarding:onboarding-1:name:prompt")
        XCTAssertEqual(turn.metadata.onboardingStep, .name)
        XCTAssertTrue(turn.metadata.onboarding)
        XCTAssertTrue(turn.metadata.automated)
        XCTAssertEqual(turn.metadata.copyRevision, 4)
        XCTAssertTrue(turn.metadata.suppressPush)
        XCTAssertTrue(turn.metadata.suppressUnread)
        XCTAssertTrue(turn.metadata.suppressBot)
    }

    func testGuideSourcePreservesFutureServerValues() throws {
        let response = try OnboardingVerificationResponse(cloudValue: [
            "sessionToken": "session-token",
            "guideSource": "futureGuide"
        ])

        XCTAssertEqual(response.session.guideSource?.rawValue, "futureGuide")
    }

    func testRestartVerificationResponseRequiresSentFlag() throws {
        XCTAssertTrue(
            try OnboardingRestartVerificationResponse(cloudValue: ["sent": true]).sent
        )
        XCTAssertThrowsError(
            try OnboardingRestartVerificationResponse(cloudValue: [:])
        ) { error in
            XCTAssertEqual(error as? OnboardingCloudContractError, .missingField("sent"))
        }
    }

    func testInvitationResolverResponseDecodesOnlySafePreviewFields() throws {
        let response = try OnboardingInvitationResolutionResponse(cloudValue: [
            "reservationId": "reservation-1",
            "guideUserId": "guide-1",
            "guideDisplayName": "Maya Rivera",
            "guideAvatarURL": "https://cdn.example.com/maya.jpg",
            "invitationMessage": "I saved you a spot.",
            "sessionToken": "must-not-be-consumed",
            "conversationId": "must-not-be-created"
        ])

        XCTAssertEqual(response.reservationId, "reservation-1")
        XCTAssertEqual(response.guideUserId, "guide-1")
        XCTAssertEqual(response.guideDisplayName, "Maya Rivera")
        XCTAssertEqual(
            response.guideAvatarURL?.absoluteString,
            "https://cdn.example.com/maya.jpg"
        )
        XCTAssertEqual(response.invitationMessage, "I saved you a spot.")
    }

    func testInvitationResolverResponseRequiresCanonicalAndSafeGuideFields() {
        let complete: [String: Any] = [
            "reservationId": "reservation-1",
            "guideUserId": "guide-1",
            "guideDisplayName": "Maya"
        ]

        for requiredField in ["reservationId", "guideUserId", "guideDisplayName"] {
            var incomplete = complete
            incomplete.removeValue(forKey: requiredField)

            XCTAssertThrowsError(
                try OnboardingInvitationResolutionResponse(cloudValue: incomplete)
            ) { error in
                XCTAssertEqual(
                    error as? OnboardingCloudContractError,
                    .missingField(requiredField)
                )
            }
        }
    }

    func testInvitationResolverForwardsEverySupportedManualInputForm() {
        let forms = [
            "reservationObjectId123",
            "legacy-reservation-code",
            "https://jibber.wtf/reservation?reservationId=reservation-1"
        ]

        for form in forms {
            let request = ResolveInvitationCodeV1(code: "  \(form)  ")
            XCTAssertEqual(request.parameters["code"] as? String, form)
            XCTAssertEqual(Set(request.parameters.keys), ["code"])
        }
    }

    func testConversationRetargetPreservesInviteAndMomentMetadata() {
        var source = DeepLinkObject(target: .moment)
        source.reservationId = "reservation-1"
        source.passId = "pass-1"
        source.momentId = "moment-1"
        source.reservationCreatorId = "guide-1"

        var retargeted = DeepLinkObject(target: .conversation, preserving: source)
        retargeted.conversationId = "conversation-1"

        XCTAssertEqual(retargeted.deepLinkTarget, .conversation)
        XCTAssertEqual(retargeted.reservationId, "reservation-1")
        XCTAssertEqual(retargeted.passId, "pass-1")
        XCTAssertEqual(retargeted.momentId, "moment-1")
        XCTAssertEqual(retargeted.reservationCreatorId, "guide-1")
        XCTAssertEqual(retargeted.conversationId, "conversation-1")
    }

    @MainActor
    func testCodeReviewScrubsSensitiveInputAndSuppressesKeyboardFocus() {
        let controller = CodeViewController()
        controller.loadViewIfNeeded()
        controller.textField.text = "1234"

        controller.prepareForReview()

        XCTAssertEqual(controller.textField.text, "")
        XCTAssertFalse(controller.shouldBecomeFirstResponder())
    }

    func testExplicitLogoutCleanupClearsSharedOnboardingHandoff() throws {
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: Config.shared.environment.groupId)
        )
        defaults.set("temporary-token", forKey: "sessionToken")
        defaults.set("conversation-1", forKey: "canonicalOnboardingConversationId")

        User.clearOnboardingHandoff()

        XCTAssertNil(defaults.string(forKey: "sessionToken"))
        XCTAssertNil(defaults.string(forKey: "canonicalOnboardingConversationId"))
    }

    private func document(
        schemaVersion: Int = OnboardingMessagingDocument.supportedSchemaVersion,
        revision: Int = 1,
        locales: [String: [String: String]]? = nil,
        guideUserId: String? = nil,
        conversation: OnboardingConversationMessagingConfiguration? = nil
    ) -> OnboardingMessagingDocument {
        OnboardingMessagingDocument(
            schemaVersion: schemaVersion,
            revision: revision,
            defaultLocale: "en",
            locales: locales ?? OnboardingMessagingDocument.emergencyFallback.locales,
            guideUserId: guideUserId,
            conversation: conversation
        )
    }
}
