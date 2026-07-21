//
//  OnboardingMessaging.swift
//  Jibber
//

import Foundation

struct OnboardingMessagingStepDefinition: Codable, Equatable, Hashable, Sendable {
    let id: OnboardingStepID
    let inputKind: OnboardingInputKind
    let progressIndex: Int?
    let titleKey: OnboardingMessageKey?
    let inputContextKey: OnboardingMessageKey?

    init(
        id: OnboardingStepID,
        inputKind: OnboardingInputKind,
        progressIndex: Int?,
        titleKey: OnboardingMessageKey? = nil,
        inputContextKey: OnboardingMessageKey? = nil
    ) {
        self.id = id
        self.inputKind = inputKind
        self.progressIndex = progressIndex
        self.titleKey = titleKey
        self.inputContextKey = inputContextKey
    }
}

struct OnboardingConversationMessagingConfiguration: Codable, Equatable, Sendable {
    static let supportedVersion = 1

    let version: Int
    let automatedPromptLabelKey: OnboardingMessageKey
    let aiGuideLabelKey: OnboardingMessageKey
    let steps: [OnboardingMessagingStepDefinition]

    static let canonicalV1 = OnboardingConversationMessagingConfiguration(
        version: Self.supportedVersion,
        automatedPromptLabelKey: .automatedOnboardingLabel,
        aiGuideLabelKey: .aiGuideLabel,
        steps: [
            OnboardingMessagingStepDefinition(id: .welcome, inputKind: .action, progressIndex: nil),
            OnboardingMessagingStepDefinition(id: .phone, inputKind: .phone, progressIndex: 0),
            OnboardingMessagingStepDefinition(id: .verification, inputKind: .verificationCode, progressIndex: 1),
            OnboardingMessagingStepDefinition(id: .name, inputKind: .name, progressIndex: 2),
            OnboardingMessagingStepDefinition(id: .faceCapture, inputKind: .faceCapture, progressIndex: 3),
            OnboardingMessagingStepDefinition(id: .completed, inputKind: .chat, progressIndex: nil)
        ]
    )

    static let canonicalV1WithPresentation = OnboardingConversationMessagingConfiguration(
        version: Self.supportedVersion,
        automatedPromptLabelKey: .automatedOnboardingLabel,
        aiGuideLabelKey: .aiGuideLabel,
        steps: Self.canonicalV1.steps.map { step in
            let presentation = Self.presentationKeys(for: step.id)
            return OnboardingMessagingStepDefinition(
                id: step.id,
                inputKind: step.inputKind,
                progressIndex: step.progressIndex,
                titleKey: presentation.title,
                inputContextKey: presentation.context
            )
        }
    )

    fileprivate func validate() throws {
        guard self.version == Self.supportedVersion else {
            throw OnboardingMessagingValidationError.invalidConversationConfiguration(
                "unsupported version \(self.version)"
            )
        }

        // V1 fixes executable behavior while allowing an additive presentation
        // mapping. Previously published documents omit these optional keys.
        let baseMatches = self.automatedPromptLabelKey == Self.canonicalV1.automatedPromptLabelKey
            && self.aiGuideLabelKey == Self.canonicalV1.aiGuideLabelKey
            && self.steps.count == Self.canonicalV1.steps.count
            && zip(self.steps, Self.canonicalV1.steps).allSatisfy { step, expected in
                step.id == expected.id
                    && step.inputKind == expected.inputKind
                    && step.progressIndex == expected.progressIndex
            }
        let presentationMatches = self.steps.allSatisfy { step in
            let expected = Self.presentationKeys(for: step.id)
            return (step.titleKey == nil || step.titleKey == expected.title)
                && (step.inputContextKey == nil || step.inputContextKey == expected.context)
        }
        guard baseMatches, presentationMatches else {
            throw OnboardingMessagingValidationError.invalidConversationConfiguration(
                "steps, labels, or input kinds do not match the native V1 contract"
            )
        }
    }

    static func presentationKeys(
        for step: OnboardingStepID
    ) -> (title: OnboardingMessageKey?, context: OnboardingMessageKey?) {
        switch step {
        case .welcome:
            return (.welcomeTitle, nil)
        case .phone:
            return (.phoneTitle, .phoneContext)
        case .verification:
            return (.codeTitle, .codeContext)
        case .name:
            return (.nameTitle, .nameContext)
        case .faceCapture:
            return (.photoTitle, .photoContext)
        case .completed:
            return (nil, nil)
        }
    }
}

enum OnboardingMessageKey: String, CaseIterable, Codable, Hashable, Sendable {
    case guideSubtitle = "guide.subtitle"
    case automatedOnboardingLabel = "conversation.automatedLabel"
    case aiGuideLabel = "conversation.aiGuideLabel"

    case welcomeStandard = "welcome.standard.body"
    case welcomeInvitation = "welcome.invitation.body"
    case welcomeMomentInvitation = "welcome.moment.body"
    case welcomeAction = "welcome.action"
    case welcomeTitle = "welcome.title"
    case welcomeAccountChoice = "welcome.choice.account"
    case welcomeInviteChoice = "welcome.choice.invite"

    case inviteContext = "invite.context"

    case phoneDefault = "phone.default.body"
    case phoneInvited = "phone.invited.body"
    case phoneCompleted = "phone.completed"
    case phoneAction = "phone.action"
    case phoneTitle = "phone.title"
    case phoneContext = "phone.context"

    case codeBody = "code.body"
    case codeCompleted = "code.completed"
    case codeAction = "code.action"
    case codeTitle = "code.title"
    case codeContext = "code.context"

    case nameFirst = "name.first.body"
    case nameLast = "name.last.body"
    case nameConfirm = "name.confirm.body"
    case nameCompleted = "name.completed"
    case nameAction = "name.action"
    case nameTitle = "name.title"
    case nameContext = "name.context"

    case photoBody = "photo.body"
    case photoCapture = "photo.capture"
    case photoReview = "photo.review"
    case photoNoFace = "photo.noFace"
    case photoNotSmiling = "photo.notSmiling"
    case photoUploadError = "photo.uploadError"
    case photoTitle = "photo.title"
    case photoContext = "photo.context"
    case photoCameraDenied = "photo.cameraDenied"
    case photoCameraRestricted = "photo.cameraRestricted"
    case photoCameraStartError = "photo.cameraStartError"
    case photoOpenSettings = "photo.openSettings"

    case navigationRevisit = "navigation.revisit"

    fileprivate var characterLimit: Int {
        switch self {
        case .welcomeAction, .welcomeAccountChoice, .welcomeInviteChoice,
             .phoneAction, .codeAction, .nameAction, .photoCapture,
             .photoReview, .photoOpenSettings:
            return 32
        case .guideSubtitle, .automatedOnboardingLabel, .aiGuideLabel,
             .navigationRevisit, .welcomeTitle, .inviteContext, .phoneTitle,
             .phoneContext, .codeTitle, .codeContext, .nameTitle,
             .nameContext, .photoTitle, .photoContext:
            return 80
        case .phoneCompleted, .codeCompleted, .nameCompleted,
             .photoNoFace, .photoNotSmiling, .photoUploadError,
             .photoCameraDenied, .photoCameraRestricted, .photoCameraStartError:
            return 160
        default:
            return 400
        }
    }
}

enum OnboardingMessageToken: String, CaseIterable, Hashable, Sendable {
    case inviterName
    case fullName
    case firstName

    fileprivate var placeholder: String {
        "{{\(self.rawValue)}}"
    }

    fileprivate var safeDefault: String {
        switch self {
        case .inviterName:
            return "Someone"
        case .fullName:
            return "that"
        case .firstName:
            return "there"
        }
    }
}

enum OnboardingMessagingSource: String, Equatable, Sendable {
    case remote
    case cache
    case bundled
    case emergency
}

enum OnboardingMessagingValidationError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case invalidRevision(Int)
    case invalidDefaultLocale(String)
    case invalidLocale(String)
    case tooManyLocales(Int)
    case missingLocale(String)
    case missingMessage(locale: String, key: String)
    case invalidMessage(locale: String, key: String, reason: String)
    case invalidGuideUserId
    case invalidConversationConfiguration(String)
    case documentTooLarge(Int)
    case invalidJSONObject

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            return "Unsupported onboarding messaging schema \(schema)."
        case .invalidRevision(let revision):
            return "Invalid onboarding messaging revision \(revision)."
        case .invalidDefaultLocale(let locale):
            return "Invalid default onboarding locale \(locale)."
        case .invalidLocale(let locale):
            return "Invalid onboarding locale \(locale)."
        case .tooManyLocales(let count):
            return "Onboarding messaging has too many locales (\(count))."
        case .missingLocale(let locale):
            return "Onboarding messaging is missing required locale \(locale)."
        case .missingMessage(let locale, let key):
            return "Onboarding locale \(locale) is missing \(key)."
        case .invalidMessage(let locale, let key, let reason):
            return "Onboarding message \(locale).\(key) is invalid: \(reason)."
        case .invalidGuideUserId:
            return "The onboarding guide user id is invalid."
        case .invalidConversationConfiguration(let reason):
            return "The onboarding conversation configuration is invalid: \(reason)."
        case .documentTooLarge(let size):
            return "Onboarding messaging is too large (\(size) bytes)."
        case .invalidJSONObject:
            return "The onboarding messaging value is not valid JSON."
        }
    }
}

struct OnboardingMessagingDocument: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = 1
    static let maximumDocumentSize = 64 * 1024
    static let maximumLocaleCount = 20

    let schemaVersion: Int
    let revision: Int
    let defaultLocale: String
    let locales: [String: [String: String]]
    let guideUserId: String?
    let conversation: OnboardingConversationMessagingConfiguration?

    init(
        schemaVersion: Int,
        revision: Int,
        defaultLocale: String,
        locales: [String: [String: String]],
        guideUserId: String? = nil,
        conversation: OnboardingConversationMessagingConfiguration? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.defaultLocale = defaultLocale
        self.locales = locales
        self.guideUserId = guideUserId
        self.conversation = conversation
    }

    func validatedData() throws -> Data {
        let data = try JSONEncoder().encode(self)
        try self.validate(encodedSize: data.count)
        return data
    }

    func validate() throws {
        let encodedSize = try JSONEncoder().encode(self).count
        try self.validate(encodedSize: encodedSize)
    }

    static func decode(from data: Data) throws -> OnboardingMessagingDocument {
        guard data.count <= self.maximumDocumentSize else {
            throw OnboardingMessagingValidationError.documentTooLarge(data.count)
        }

        let document = try JSONDecoder().decode(OnboardingMessagingDocument.self, from: data)
        try document.validate(encodedSize: data.count)
        return document
    }

    static func decode(jsonObject: Any) throws -> OnboardingMessagingDocument {
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw OnboardingMessagingValidationError.invalidJSONObject
        }

        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        return try self.decode(from: data)
    }

    private func validate(encodedSize: Int) throws {
        guard encodedSize <= Self.maximumDocumentSize else {
            throw OnboardingMessagingValidationError.documentTooLarge(encodedSize)
        }
        guard self.schemaVersion == Self.supportedSchemaVersion else {
            throw OnboardingMessagingValidationError.unsupportedSchema(self.schemaVersion)
        }
        guard self.revision >= 0 else {
            throw OnboardingMessagingValidationError.invalidRevision(self.revision)
        }
        guard Self.isValidLocaleIdentifier(self.defaultLocale) else {
            throw OnboardingMessagingValidationError.invalidDefaultLocale(self.defaultLocale)
        }
        guard !self.locales.isEmpty,
              self.locales.count <= Self.maximumLocaleCount else {
            throw OnboardingMessagingValidationError.tooManyLocales(self.locales.count)
        }

        for locale in self.locales.keys where !Self.isValidLocaleIdentifier(locale) {
            throw OnboardingMessagingValidationError.invalidLocale(locale)
        }

        guard let english = self.messages(matching: "en") else {
            throw OnboardingMessagingValidationError.missingLocale("en")
        }
        guard let defaultMessages = self.messages(matching: self.defaultLocale) else {
            throw OnboardingMessagingValidationError.missingLocale(self.defaultLocale)
        }

        try self.validateRequiredMessages(english, locale: "en")
        if Self.normalizedLocale(self.defaultLocale) != "en" {
            try self.validateRequiredMessages(defaultMessages, locale: self.defaultLocale)
        }

        for (locale, messages) in self.locales {
            for (key, message) in messages {
                try Self.validateMessage(message, locale: locale, key: key)
            }
        }

        if let guideUserId = self.guideUserId {
            let trimmed = guideUserId.trimmingCharacters(in: .whitespacesAndNewlines)
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            guard !trimmed.isEmpty,
                  trimmed.count <= 128,
                  trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw OnboardingMessagingValidationError.invalidGuideUserId
            }
        }

        if let conversation = self.conversation {
            try conversation.validate()
            try self.validateConversationLabels(
                conversation,
                messages: english,
                locale: "en"
            )
            if Self.normalizedLocale(self.defaultLocale) != "en" {
                try self.validateConversationLabels(
                    conversation,
                    messages: defaultMessages,
                    locale: self.defaultLocale
                )
            }
        }
    }

    fileprivate func messages(matching locale: String) -> [String: String]? {
        let normalized = Self.normalizedLocale(locale)
        return self.locales.first { key, _ in
            Self.normalizedLocale(key) == normalized
        }?.value
    }

    private func validateRequiredMessages(
        _ messages: [String: String],
        locale: String
    ) throws {
        for key in OnboardingMessageKey.legacyRequiredCases where messages[key.rawValue] == nil {
            throw OnboardingMessagingValidationError.missingMessage(
                locale: locale,
                key: key.rawValue
            )
        }
    }

    private func validateConversationLabels(
        _ configuration: OnboardingConversationMessagingConfiguration,
        messages: [String: String],
        locale: String
    ) throws {
        let keys = [
            configuration.automatedPromptLabelKey,
            configuration.aiGuideLabelKey
        ] + configuration.steps.flatMap { step in
            [step.titleKey, step.inputContextKey].compactMap { $0 }
        }
        for key in keys where messages[key.rawValue] == nil {
            throw OnboardingMessagingValidationError.missingMessage(
                locale: locale,
                key: key.rawValue
            )
        }
    }

    private static func validateMessage(
        _ message: String,
        locale: String,
        key: String
    ) throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OnboardingMessagingValidationError.invalidMessage(
                locale: locale,
                key: key,
                reason: "empty"
            )
        }

        let limit = OnboardingMessageKey(rawValue: key)?.characterLimit ?? 400
        guard message.count <= limit else {
            throw OnboardingMessagingValidationError.invalidMessage(
                locale: locale,
                key: key,
                reason: "longer than \(limit) characters"
            )
        }

        let hasUnsupportedControlCharacter = message.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                && scalar.value != 0x09
                && scalar.value != 0x0A
        }
        guard !hasUnsupportedControlCharacter,
              !message.contains("<"),
              !message.contains(">"),
              !message.localizedCaseInsensitiveContains("http://"),
              !message.localizedCaseInsensitiveContains("https://"),
              !message.contains("]("),
              !message.contains("**"),
              !message.contains("`") else {
            throw OnboardingMessagingValidationError.invalidMessage(
                locale: locale,
                key: key,
                reason: "must be plain text"
            )
        }

        let expression = try NSRegularExpression(pattern: #"\{\{([A-Za-z][A-Za-z0-9]*)\}\}"#)
        let fullRange = NSRange(message.startIndex..<message.endIndex, in: message)
        let matches = expression.matches(in: message, range: fullRange)
        let allowedTokens = Set(OnboardingMessageToken.allCases.map(\.rawValue))
        let messageAsNSString = message as NSString

        for match in matches {
            let token = messageAsNSString.substring(with: match.range(at: 1))
            guard allowedTokens.contains(token) else {
                throw OnboardingMessagingValidationError.invalidMessage(
                    locale: locale,
                    key: key,
                    reason: "unknown token \(token)"
                )
            }
        }

        let textWithoutValidTokens = expression.stringByReplacingMatches(
            in: message,
            range: fullRange,
            withTemplate: ""
        )
        guard !textWithoutValidTokens.contains("{{"),
              !textWithoutValidTokens.contains("}}") else {
            throw OnboardingMessagingValidationError.invalidMessage(
                locale: locale,
                key: key,
                reason: "malformed token"
            )
        }
    }

    private static func normalizedLocale(_ locale: String) -> String {
        locale.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func isValidLocaleIdentifier(_ locale: String) -> Bool {
        let trimmed = locale.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return !trimmed.isEmpty
            && trimmed.count <= 35
            && trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

private extension OnboardingMessageKey {
    /// Copy required by the original onboardingMessagingV1 contract. New
    /// conversation labels are required only when `conversation` is present,
    /// keeping already-published V1 documents valid during rollout.
    static let optionalPresentationCases: Set<Self> = [
        .welcomeTitle,
        .welcomeAccountChoice,
        .welcomeInviteChoice,
        .inviteContext,
        .phoneTitle,
        .phoneContext,
        .codeTitle,
        .codeContext,
        .nameTitle,
        .nameContext,
        .photoTitle,
        .photoContext,
        .photoCameraDenied,
        .photoCameraRestricted,
        .photoCameraStartError,
        .photoOpenSettings
    ]

    static let legacyRequiredCases = Self.allCases.filter {
        $0 != .automatedOnboardingLabel
            && $0 != .aiGuideLabel
            && $0 != .welcomeAction
            && !Self.optionalPresentationCases.contains($0)
    }
}

struct OnboardingMessaging: Equatable, Sendable {
    let document: OnboardingMessagingDocument
    let source: OnboardingMessagingSource
    private let selectedLocale: String

    init(
        document: OnboardingMessagingDocument,
        source: OnboardingMessagingSource,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) throws {
        try document.validate()
        self.document = document
        self.source = source
        self.selectedLocale = Self.selectLocale(
            from: document,
            preferredLanguages: preferredLanguages
        )
    }

    var revision: Int {
        self.document.revision
    }

    var guideUserId: String? {
        self.document.guideUserId
    }

    var localeIdentifier: String {
        self.selectedLocale
    }

    var conversationConfiguration: OnboardingConversationMessagingConfiguration {
        self.document.conversation ?? .canonicalV1
    }

    var automatedPromptLabel: String {
        self.text(for: self.conversationConfiguration.automatedPromptLabelKey)
    }

    var aiGuideLabel: String {
        self.text(for: self.conversationConfiguration.aiGuideLabelKey)
    }

    func inputKind(for stepID: OnboardingStepID) -> OnboardingInputKind? {
        self.conversationConfiguration.steps.first(where: { $0.id == stepID })?.inputKind
    }

    func title(for stepID: OnboardingStepID) -> String {
        let configured = self.conversationConfiguration.steps
            .first(where: { $0.id == stepID })?
            .titleKey
        let fallback = OnboardingConversationMessagingConfiguration
            .presentationKeys(for: stepID)
            .title
        guard let key = configured ?? fallback else { return "" }
        return self.text(for: key)
    }

    func inputContext(
        for stepID: OnboardingStepID,
        replacements: [OnboardingMessageToken: String] = [:]
    ) -> String {
        let configured = self.conversationConfiguration.steps
            .first(where: { $0.id == stepID })?
            .inputContextKey
        let fallback = OnboardingConversationMessagingConfiguration
            .presentationKeys(for: stepID)
            .context
        guard let key = configured ?? fallback else { return "" }
        return self.text(for: key, replacements: replacements)
    }

    func text(
        for key: OnboardingMessageKey,
        replacements: [OnboardingMessageToken: String] = [:]
    ) -> String {
        let selectedMessages = self.document.messages(matching: self.selectedLocale)
        let defaultMessages = self.document.messages(matching: self.document.defaultLocale)
        let englishMessages = self.document.messages(matching: "en")
        var text = selectedMessages?[key.rawValue]
            ?? defaultMessages?[key.rawValue]
            ?? englishMessages?[key.rawValue]
            ?? OnboardingMessagingDocument.emergencyFallback.locales["en"]?[key.rawValue]
            ?? ""

        for token in OnboardingMessageToken.allCases {
            text = text.replacingOccurrences(
                of: token.placeholder,
                with: replacements[token] ?? token.safeDefault
            )
        }
        return text
    }

    private static func selectLocale(
        from document: OnboardingMessagingDocument,
        preferredLanguages: [String]
    ) -> String {
        let available = Array(document.locales.keys)

        for preferred in preferredLanguages {
            let normalizedPreferred = Self.normalizedLocale(preferred)
            if let exact = available.first(where: {
                Self.normalizedLocale($0) == normalizedPreferred
            }) {
                return exact
            }

            let language = normalizedPreferred.split(separator: "-").first.map(String.init)
            if let language,
               let match = available.first(where: {
                   Self.normalizedLocale($0).split(separator: "-").first.map(String.init)
                       == language
               }) {
                return match
            }
        }

        return available.first(where: {
            Self.normalizedLocale($0) == Self.normalizedLocale(document.defaultLocale)
        }) ?? document.defaultLocale
    }

    private static func normalizedLocale(_ locale: String) -> String {
        locale.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

struct OnboardingMessagingResolution: Equatable, Sendable {
    let document: OnboardingMessagingDocument
    let source: OnboardingMessagingSource
}

enum OnboardingMessagingResolver {
    static func resolve(
        remote: OnboardingMessagingDocument?,
        cached: OnboardingMessagingDocument?,
        fallback: OnboardingMessagingDocument
    ) throws -> OnboardingMessagingResolution {
        try fallback.validate()

        let validatedCached: OnboardingMessagingDocument?
        if let cached, (try? cached.validate()) != nil {
            validatedCached = cached
        } else {
            validatedCached = nil
        }

        let baseline: OnboardingMessagingResolution
        if let validatedCached,
           validatedCached.revision >= fallback.revision {
            baseline = OnboardingMessagingResolution(
                document: validatedCached,
                source: .cache
            )
        } else {
            baseline = OnboardingMessagingResolution(
                document: fallback,
                source: .bundled
            )
        }

        guard let remote, (try? remote.validate()) != nil else {
            return baseline
        }

        if remote.revision > baseline.document.revision {
            return OnboardingMessagingResolution(document: remote, source: .remote)
        }
        if remote.revision == baseline.document.revision,
           remote == baseline.document {
            return OnboardingMessagingResolution(document: remote, source: .remote)
        }

        // A lower revision is stale. Reusing a revision with different content
        // is also rejected; administrators roll back by publishing the old copy
        // under a new, higher revision.
        return baseline
    }
}

extension OnboardingMessagingDocument {
    static let emergencyFallback = OnboardingMessagingDocument(
        schemaVersion: OnboardingMessagingDocument.supportedSchemaVersion,
        revision: 0,
        defaultLocale: "en",
        locales: [
            "en": [
                OnboardingMessageKey.guideSubtitle.rawValue: "Setting up Jibber",
                OnboardingMessageKey.automatedOnboardingLabel.rawValue: "Automated onboarding",
                OnboardingMessageKey.aiGuideLabel.rawValue: "AI guide",
                OnboardingMessageKey.welcomeStandard.rawValue: "Welcome to Jibber. I’ll help you get set up.",
                OnboardingMessageKey.welcomeInvitation.rawValue: "{{inviterName}} invited you to connect on Jibber. I’ll help you finish setting up your account.",
                OnboardingMessageKey.welcomeMomentInvitation.rawValue: "Connect with {{inviterName}} to continue. You can return to the Moment without changing anything.",
                OnboardingMessageKey.welcomeAction.rawValue: "Continue",
                OnboardingMessageKey.welcomeTitle.rawValue: "Welcome",
                OnboardingMessageKey.welcomeAccountChoice.rawValue: "Log in or sign up",
                OnboardingMessageKey.welcomeInviteChoice.rawValue: "Enter invite code",
                OnboardingMessageKey.inviteContext.rawValue: "Invite code",
                OnboardingMessageKey.phoneDefault.rawValue: "What’s your phone number?",
                OnboardingMessageKey.phoneInvited.rawValue: "Confirm your phone number.",
                OnboardingMessageKey.phoneCompleted.rawValue: "Perfect — I sent you a code.",
                OnboardingMessageKey.phoneAction.rawValue: "Continue",
                OnboardingMessageKey.phoneTitle.rawValue: "Phone",
                OnboardingMessageKey.phoneContext.rawValue: "Mobile number",
                OnboardingMessageKey.codeBody.rawValue: "Enter the code Jibber texted you.",
                OnboardingMessageKey.codeCompleted.rawValue: "You’re verified.",
                OnboardingMessageKey.codeAction.rawValue: "Continue",
                OnboardingMessageKey.codeTitle.rawValue: "Verification Code",
                OnboardingMessageKey.codeContext.rawValue: "Code sent to %@",
                OnboardingMessageKey.nameFirst.rawValue: "What’s your name?",
                OnboardingMessageKey.nameLast.rawValue: "Thanks, {{firstName}}. What’s your last name?",
                OnboardingMessageKey.nameConfirm.rawValue: "Does {{fullName}} look right?",
                OnboardingMessageKey.nameCompleted.rawValue: "Great to meet you, {{firstName}}. Let’s get Jibber set up.",
                OnboardingMessageKey.nameAction.rawValue: "Continue",
                OnboardingMessageKey.nameTitle.rawValue: "Name",
                OnboardingMessageKey.nameContext.rawValue: "How {{inviterName}} will know you",
                OnboardingMessageKey.photoBody.rawValue: "One last thing—let’s take a profile photo so people know it’s you.",
                OnboardingMessageKey.photoCapture.rawValue: "Capture",
                OnboardingMessageKey.photoReview.rawValue: "Use this photo",
                OnboardingMessageKey.photoNoFace.rawValue: "Move into the frame so I can see your face.",
                OnboardingMessageKey.photoNotSmiling.rawValue: "Smile when you’re ready.",
                OnboardingMessageKey.photoUploadError.rawValue: "I couldn’t save that photo. Try again.",
                OnboardingMessageKey.photoTitle.rawValue: "Face Capture",
                OnboardingMessageKey.photoContext.rawValue: "Center your face",
                OnboardingMessageKey.photoCameraDenied.rawValue: "Camera access is off. Open Settings to take your profile photo.",
                OnboardingMessageKey.photoCameraRestricted.rawValue: "Camera access is restricted on this device.",
                OnboardingMessageKey.photoCameraStartError.rawValue: "I couldn’t start the camera. Try again.",
                OnboardingMessageKey.photoOpenSettings.rawValue: "Open Settings",
                OnboardingMessageKey.navigationRevisit.rawValue: "Swipe down to revisit"
            ]
        ],
        conversation: .canonicalV1WithPresentation
    )
}
