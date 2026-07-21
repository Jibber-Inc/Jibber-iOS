//
//  Onboarding+CloudCalls.swift
//  Benji
//
//  Created by Benji Dodgson on 2/11/20.
//  Copyright © 2020 Benjamin Dodgson. All rights reserved.
//

import Foundation
import ParseCore
import PhoneNumberKit

/// Stable identifiers shared by Parse Cloud, the App Clip, and the full app.
/// Raw values are persisted in message metadata and must not be renamed.
enum OnboardingStepID: String, CaseIterable, Codable, Hashable, Sendable {
    case welcome
    case phone
    case verification
    case name
    case faceCapture
    case completed
}

/// Input types the native clients know how to render. Server configuration can
/// select from this allowlist, but cannot introduce executable UI behavior.
enum OnboardingInputKind: String, CaseIterable, Codable, Hashable, Sendable {
    case action
    case phone
    case verificationCode
    case name
    case faceCapture
    case review
    case chat
}

struct OnboardingEntryContext: Codable, Equatable, Sendable {
    let reservationId: String?
    let passId: String?
    let momentId: String?

    init(
        reservationId: String? = nil,
        passId: String? = nil,
        momentId: String? = nil
    ) {
        self.reservationId = reservationId
        self.passId = passId
        self.momentId = momentId
    }

    fileprivate var cloudParameters: [String: Any] {
        var parameters: [String: Any] = [:]
        if let reservationId = Self.nonEmpty(self.reservationId) {
            parameters["reservationId"] = reservationId
        }
        if let passId = Self.nonEmpty(self.passId) {
            parameters["passId"] = passId
        }
        if let momentId = Self.nonEmpty(self.momentId) {
            parameters["momentId"] = momentId
        }
        return parameters
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A forward-compatible guide source. Known values are exposed as constants,
/// while an unfamiliar server value can still be retained for diagnostics.
struct OnboardingGuideSource: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let reservation = Self(rawValue: "reservation")
    static let pass = Self(rawValue: "pass")
    static let moment = Self(rawValue: "moment")
    static let maya = Self(rawValue: "maya")
    static let configuredAgent = Self(rawValue: "configuredAgent")

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

struct OnboardingConversationSession: Codable, Equatable, Sendable {
    let onboardingSessionId: String?
    let conversationId: String?
    let guideUserId: String?
    let guideSource: OnboardingGuideSource?
    let messagingRevision: Int?
    /// Optional validated snapshot locked when the server created this
    /// session. New servers include it so a fresh device can restore old copy
    /// after Parse Config advances; legacy servers safely omit it.
    let messagingDocumentJSON: String?
    let pendingPhoneNumber: String?
    let reachedStep: OnboardingStepID?
    let completed: Bool

    init(
        onboardingSessionId: String? = nil,
        conversationId: String? = nil,
        guideUserId: String? = nil,
        guideSource: OnboardingGuideSource? = nil,
        messagingRevision: Int? = nil,
        messagingDocumentJSON: String? = nil,
        pendingPhoneNumber: String? = nil,
        reachedStep: OnboardingStepID? = nil,
        completed: Bool = false
    ) {
        self.onboardingSessionId = onboardingSessionId
        self.conversationId = conversationId
        self.guideUserId = guideUserId
        self.guideSource = guideSource
        self.messagingRevision = messagingRevision
        self.messagingDocumentJSON = messagingDocumentJSON
        self.pendingPhoneNumber = pendingPhoneNumber
        self.reachedStep = reachedStep
        self.completed = completed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            onboardingSessionId: try container.decodeIfPresent(
                String.self,
                forKey: .onboardingSessionId
            ),
            conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId),
            guideUserId: try container.decodeIfPresent(String.self, forKey: .guideUserId),
            guideSource: try container.decodeIfPresent(
                OnboardingGuideSource.self,
                forKey: .guideSource
            ),
            messagingRevision: try container.decodeIfPresent(
                Int.self,
                forKey: .messagingRevision
            ),
            messagingDocumentJSON: try container.decodeIfPresent(
                String.self,
                forKey: .messagingDocumentJSON
            ),
            pendingPhoneNumber: try container.decodeIfPresent(
                String.self,
                forKey: .pendingPhoneNumber
            ),
            reachedStep: try container.decodeIfPresent(OnboardingStepID.self, forKey: .reachedStep),
            completed: try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        )
    }

    fileprivate init(cloudDictionary: [String: Any]) {
        self.init(
            onboardingSessionId: OnboardingCloudValue.string(
                cloudDictionary["onboardingSessionId"]
            ),
            conversationId: OnboardingCloudValue.string(cloudDictionary["conversationId"]),
            guideUserId: OnboardingCloudValue.string(cloudDictionary["guideUserId"]),
            guideSource: OnboardingCloudValue.string(cloudDictionary["guideSource"]).map {
                OnboardingGuideSource(rawValue: $0)
            },
            messagingRevision: OnboardingCloudValue.int(cloudDictionary["messagingRevision"]),
            messagingDocumentJSON: OnboardingCloudValue.jsonString(
                cloudDictionary["messagingDocumentJSON"]
                    ?? cloudDictionary["messagingDocument"]
            ),
            pendingPhoneNumber: OnboardingCloudValue.string(
                cloudDictionary["pendingPhoneNumber"]
            ),
            reachedStep: OnboardingCloudValue.string(cloudDictionary["reachedStep"]).flatMap {
                OnboardingStepID(rawValue: $0)
            },
            completed: OnboardingCloudValue.bool(cloudDictionary["completed"]) ?? false
        )
    }
}

struct OnboardingConversationTurnMetadata: Codable, Equatable, Sendable {
    let onboarding: Bool
    let automated: Bool
    let onboardingStep: OnboardingStepID?
    let copyRevision: Int?
    let suppressPush: Bool
    let suppressUnread: Bool
    let suppressBot: Bool

    init(
        onboarding: Bool = false,
        automated: Bool = false,
        onboardingStep: OnboardingStepID? = nil,
        copyRevision: Int? = nil,
        suppressPush: Bool = false,
        suppressUnread: Bool = false,
        suppressBot: Bool = false
    ) {
        self.onboarding = onboarding
        self.automated = automated
        self.onboardingStep = onboardingStep
        self.copyRevision = copyRevision
        self.suppressPush = suppressPush
        self.suppressUnread = suppressUnread
        self.suppressBot = suppressBot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            onboarding: try container.decodeIfPresent(Bool.self, forKey: .onboarding) ?? false,
            automated: try container.decodeIfPresent(Bool.self, forKey: .automated) ?? false,
            onboardingStep: try container.decodeIfPresent(
                OnboardingStepID.self,
                forKey: .onboardingStep
            ),
            copyRevision: try container.decodeIfPresent(Int.self, forKey: .copyRevision),
            suppressPush: try container.decodeIfPresent(Bool.self, forKey: .suppressPush) ?? false,
            suppressUnread: try container.decodeIfPresent(
                Bool.self,
                forKey: .suppressUnread
            ) ?? false,
            suppressBot: try container.decodeIfPresent(Bool.self, forKey: .suppressBot) ?? false
        )
    }

    fileprivate init(cloudDictionary: [String: Any]) {
        self.init(
            onboarding: OnboardingCloudValue.bool(cloudDictionary["onboarding"]) ?? false,
            automated: OnboardingCloudValue.bool(cloudDictionary["automated"]) ?? false,
            onboardingStep: OnboardingCloudValue.string(
                cloudDictionary["onboardingStep"]
            ).flatMap(OnboardingStepID.init(rawValue:)),
            copyRevision: OnboardingCloudValue.int(cloudDictionary["copyRevision"]),
            suppressPush: OnboardingCloudValue.bool(cloudDictionary["suppressPush"]) ?? false,
            suppressUnread: OnboardingCloudValue.bool(cloudDictionary["suppressUnread"]) ?? false,
            suppressBot: OnboardingCloudValue.bool(cloudDictionary["suppressBot"]) ?? false
        )
    }
}

struct OnboardingConversationTurn: Codable, Equatable, Identifiable, Sendable {
    let objectId: String?
    let clientMessageId: String?
    let authorId: String?
    let text: String
    let contentType: String
    let createdAt: String?
    let metadata: OnboardingConversationTurnMetadata

    /// `clientMessageId` is deterministic for onboarding seed messages. The
    /// Parse object id remains a safe fallback for older server responses.
    var id: String {
        self.clientMessageId ?? self.objectId ?? ""
    }

    init(
        objectId: String? = nil,
        clientMessageId: String? = nil,
        authorId: String? = nil,
        text: String,
        contentType: String = "text",
        createdAt: String? = nil,
        metadata: OnboardingConversationTurnMetadata = .init()
    ) {
        self.objectId = objectId
        self.clientMessageId = clientMessageId
        self.authorId = authorId
        self.text = text
        self.contentType = contentType
        self.createdAt = createdAt
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            objectId: try container.decodeIfPresent(String.self, forKey: .objectId),
            clientMessageId: try container.decodeIfPresent(String.self, forKey: .clientMessageId),
            authorId: try container.decodeIfPresent(String.self, forKey: .authorId),
            text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
            contentType: try container.decodeIfPresent(String.self, forKey: .contentType) ?? "text",
            createdAt: try container.decodeIfPresent(String.self, forKey: .createdAt),
            metadata: try container.decodeIfPresent(
                OnboardingConversationTurnMetadata.self,
                forKey: .metadata
            ) ?? .init()
        )
    }

    fileprivate init?(cloudDictionary: [String: Any]) {
        let objectId = OnboardingCloudValue.string(cloudDictionary["objectId"])
        let clientMessageId = OnboardingCloudValue.string(cloudDictionary["clientMessageId"])
        guard objectId != nil || clientMessageId != nil,
              let text = OnboardingCloudValue.string(cloudDictionary["text"]) else {
            return nil
        }

        self.init(
            objectId: objectId,
            clientMessageId: clientMessageId,
            authorId: OnboardingCloudValue.string(cloudDictionary["authorId"]),
            text: text,
            contentType: OnboardingCloudValue.string(cloudDictionary["contentType"]) ?? "text",
            createdAt: OnboardingCloudValue.dateString(cloudDictionary["createdAt"]),
            metadata: OnboardingCloudValue.dictionary(cloudDictionary["metadata"]).map {
                OnboardingConversationTurnMetadata(cloudDictionary: $0)
            } ?? .init()
        )
    }
}

enum OnboardingCloudContractError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The onboarding server response is invalid."
        case .missingField(let field):
            return "The onboarding server response is missing \(field)."
        }
    }
}

struct OnboardingVerificationResponse: Equatable, Sendable {
    let sessionToken: String
    let session: OnboardingConversationSession
    /// True when verification resumed an account that had already completed
    /// onboarding. Those users should open their canonical conversation rather
    /// than entering the onboarding state machine again.
    let existingUser: Bool

    init(cloudValue: Any) throws {
        guard let dictionary = OnboardingCloudValue.dictionary(cloudValue) else {
            throw OnboardingCloudContractError.invalidResponse
        }
        guard let sessionToken = OnboardingCloudValue.string(dictionary["sessionToken"]),
              !sessionToken.isEmpty else {
            throw OnboardingCloudContractError.missingField("sessionToken")
        }

        self.sessionToken = sessionToken
        self.session = OnboardingConversationSession(cloudDictionary: dictionary)
        self.existingUser = OnboardingCloudValue.bool(dictionary["existingUser"]) ?? false
    }
}

struct OnboardingConversationSyncResponse: Equatable, Sendable {
    let session: OnboardingConversationSession
    let turns: [OnboardingConversationTurn]

    init(cloudValue: Any) throws {
        guard let dictionary = OnboardingCloudValue.dictionary(cloudValue) else {
            throw OnboardingCloudContractError.invalidResponse
        }

        self.session = OnboardingConversationSession(cloudDictionary: dictionary)
        self.turns = OnboardingCloudValue.array(dictionary["turns"]).compactMap {
            OnboardingCloudValue.dictionary($0).flatMap(OnboardingConversationTurn.init(cloudDictionary:))
        }
    }
}

struct OnboardingRestartVerificationResponse: Equatable, Sendable {
    let sent: Bool

    init(cloudValue: Any) throws {
        guard let dictionary = OnboardingCloudValue.dictionary(cloudValue) else {
            throw OnboardingCloudContractError.invalidResponse
        }
        guard let sent = OnboardingCloudValue.bool(dictionary["sent"]) else {
            throw OnboardingCloudContractError.missingField("sent")
        }
        self.sent = sent
    }
}

/// Safe, non-mutating preview returned before authentication when somebody enters an
/// invitation manually. Only the canonical reservation id is carried into verification;
/// raw codes and URLs are never persisted in onboarding state.
struct OnboardingInvitationResolutionResponse: Equatable, Sendable {
    let reservationId: String
    let guideUserId: String
    let guideDisplayName: String
    let guideAvatarURL: URL?
    let invitationMessage: String?

    init(cloudValue: Any) throws {
        guard let dictionary = OnboardingCloudValue.dictionary(cloudValue) else {
            throw OnboardingCloudContractError.invalidResponse
        }
        guard let reservationId = OnboardingCloudValue.string(dictionary["reservationId"]) else {
            throw OnboardingCloudContractError.missingField("reservationId")
        }
        guard let guideUserId = OnboardingCloudValue.string(dictionary["guideUserId"]) else {
            throw OnboardingCloudContractError.missingField("guideUserId")
        }
        guard let guideDisplayName = OnboardingCloudValue.string(
            dictionary["guideDisplayName"]
        ) else {
            throw OnboardingCloudContractError.missingField("guideDisplayName")
        }

        self.reservationId = reservationId
        self.guideUserId = guideUserId
        self.guideDisplayName = guideDisplayName
        self.guideAvatarURL = OnboardingCloudValue.string(
            dictionary["guideAvatarURL"]
        ).flatMap(URL.init(string:))
        self.invitationMessage = OnboardingCloudValue.string(
            dictionary["invitationMessage"]
        )
    }
}

struct OnboardingFinalizationResponse: Equatable, Sendable {
    let session: OnboardingConversationSession
    let userObjectId: String?

    init(cloudValue: Any) throws {
        guard let dictionary = OnboardingCloudValue.dictionary(cloudValue) else {
            throw OnboardingCloudContractError.invalidResponse
        }

        self.session = OnboardingConversationSession(cloudDictionary: dictionary)
        if let user = dictionary["user"] as? User {
            self.userObjectId = user.objectId
        } else if let user = OnboardingCloudValue.dictionary(dictionary["user"]) {
            self.userObjectId = OnboardingCloudValue.string(user["objectId"])
                ?? OnboardingCloudValue.string(user["id"])
        } else {
            self.userObjectId = nil
        }
    }
}

private enum OnboardingCloudValue {
    static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        guard let dictionary = value as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            guard let key = key as? String else { continue }
            result[key] = value
        }
        return result
    }

    static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    static func string(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        return (value as? NSNumber)?.intValue
    }

    static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    static func jsonString(_ value: Any?) -> String? {
        if let string = self.string(value) {
            return string
        }
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func dateString(_ value: Any?) -> String? {
        if let string = self.string(value) { return string }
        guard let date = value as? Date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }
}

struct SendCode: CloudFunction {
    
    typealias ReturnType = Any
    
    let phoneNumber: PhoneNumber
    let region: String
    let installationId: String
    
    func makeRequest(andUpdate statusables: [Statusable] = [],
                     viewsToIgnore: [UIView] = []) async throws -> Any {

        let phoneString = PhoneKit.shared.format(self.phoneNumber, toType: .e164)
        
        let params = ["phoneNumber": phoneString,
                      "installationId": self.installationId,
                      "region": self.region]
        
        let result = try await self.makeRequest(andUpdate: statusables,
                                                params: params,
                                                callName: "sendCode",
                                                delayInterval: 0.0,
                                                viewsToIgnore: viewsToIgnore)
        return result
    }
}

struct VerifyCode: CloudFunction {

    typealias ReturnType = [String: String]
    
    let code: String
    let phoneNumber: PhoneNumber
    let installationId: String

    func makeRequest(andUpdate statusables: [Statusable] = [],
                     viewsToIgnore: [UIView] = []) async throws -> [String: String] {
        
        let params: [String: Any] = ["authCode": self.code,
                                     "installationId": self.installationId,
                                     "phoneNumber": PhoneKit.shared.format(self.phoneNumber, toType: .e164)]
        
        let result = try await self.makeRequest(andUpdate: statusables,
                                                params: params,
                                                callName: "validateCode",
                                                viewsToIgnore: viewsToIgnore)
        
        if let dict = result as? [String: String],
           let token = dict["sessionToken"],
           !token.isEmpty {
            return dict
        } else if let token = result as? String {
            var dict: [String: String] = [:]
            dict["sessionToken"] = token
            return dict
        } else {
            throw(ClientError.apiError(detail: "Verify code error"))
        }
    }
}

/// Canonical-conversation verification. The legacy `VerifyCode` call remains
/// unchanged for released clients while this endpoint rolls out independently.
struct ValidateCodeV2: CloudFunction {
    typealias ReturnType = OnboardingVerificationResponse

    let code: String
    let phoneNumber: PhoneNumber
    let context: OnboardingEntryContext
    let locale: String?

    init(
        code: String,
        phoneNumber: PhoneNumber,
        context: OnboardingEntryContext = .init(),
        locale: String? = nil
    ) {
        self.code = code
        self.phoneNumber = phoneNumber
        self.context = context
        self.locale = locale
    }

    var parameters: [String: Any] {
        var parameters = self.context.cloudParameters
        parameters["authCode"] = self.code
        parameters["phoneNumber"] = PhoneKit.shared.format(self.phoneNumber, toType: .e164)
        if let locale = self.locale?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locale.isEmpty {
            parameters["locale"] = locale
        }
        return parameters
    }

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> OnboardingVerificationResponse {
        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: self.parameters,
            callName: "validateCodeV2",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        return try OnboardingVerificationResponse(cloudValue: result)
    }
}

/// Resolves an object id, legacy invitation code, or full invitation URL without
/// claiming it or creating private conversation state.
struct ResolveInvitationCodeV1: CloudFunction {
    typealias ReturnType = OnboardingInvitationResolutionResponse

    let code: String

    var parameters: [String: Any] {
        ["code": self.code.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> OnboardingInvitationResolutionResponse {
        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: self.parameters,
            callName: "resolveInvitationCodeV1",
            delayInterval: 0,
            viewsToIgnore: viewsToIgnore
        )
        return try OnboardingInvitationResolutionResponse(cloudValue: result)
    }
}

struct SyncOnboardingConversationV1: CloudFunction {
    typealias ReturnType = OnboardingConversationSyncResponse

    let locale: String?

    init(locale: String? = nil) {
        self.locale = locale
    }

    var parameters: [String: Any] {
        guard let locale = self.locale?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locale.isEmpty else {
            return [:]
        }
        return ["locale": locale]
    }

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> OnboardingConversationSyncResponse {
        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: self.parameters,
            callName: "syncOnboardingConversationV1",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        return try OnboardingConversationSyncResponse(cloudValue: result)
    }
}

struct RestartOnboardingVerificationV1: CloudFunction {
    typealias ReturnType = OnboardingRestartVerificationResponse

    let phoneNumber: PhoneNumber

    var parameters: [String: Any] {
        ["phoneNumber": PhoneKit.shared.format(self.phoneNumber, toType: .e164)]
    }

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> OnboardingRestartVerificationResponse {
        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: self.parameters,
            callName: "restartOnboardingVerificationV1",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        return try OnboardingRestartVerificationResponse(cloudValue: result)
    }
}

struct FinalizeOnboarding: CloudFunction {

    typealias ReturnType = Any
    
    let reservationId: String
    let passId: String
    let momentId: String
    var forceUpgrade: Bool

    init(
        reservationId: String,
        passId: String,
        momentId: String = "",
        forceUpgrade: Bool = false
    ) {
        self.reservationId = reservationId
        self.passId = passId
        self.momentId = momentId
        self.forceUpgrade = forceUpgrade
    }

    @discardableResult
    func makeRequest(andUpdate statusables: [Statusable], viewsToIgnore: [UIView]) async throws -> Any {
        
        let params: [String: Any] = ["passId": self.passId,
                                     "reservationId": self.reservationId,
                                     "momentId": self.momentId,
                                     "forceUpgrade": self.forceUpgrade]
        
        _ = try await self.makeRequest(andUpdate: statusables,
                                       params: params,
                                       callName: "finalizeUserOnboarding",
                                       delayInterval: 0.0,
                                       viewsToIgnore: viewsToIgnore)

        guard let user = User.current() else {
            throw ClientError.message(detail: "No user found.")
        }

        // Refresh the user so it's activation status is properly reflected.
        return try await user.fetchInBackground()
    }

}

/// Completes the server-owned onboarding session without resending invitation
/// context from the client. Legacy `FinalizeOnboarding` remains available.
struct FinalizeOnboardingV2: CloudFunction {
    typealias ReturnType = OnboardingFinalizationResponse

    let locale: String?

    init(locale: String? = nil) {
        self.locale = locale
    }

    var parameters: [String: Any] {
        guard let locale = self.locale?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locale.isEmpty else {
            return [:]
        }
        return ["locale": locale]
    }

    @discardableResult
    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> OnboardingFinalizationResponse {
        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: self.parameters,
            callName: "finalizeUserOnboardingV2",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        return try OnboardingFinalizationResponse(cloudValue: result)
    }
}

struct PreparePersonInvitation: CloudFunction {

    typealias ReturnType = [String: Any]

    let message: String
    let requestId: String
    let reservationId: String?

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> [String: Any] {
        var params: [String: Any] = [
            "message": self.message,
            "requestId": self.requestId
        ]
        if let reservationId {
            params["reservationId"] = reservationId
        }

        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: params,
            callName: "preparePersonInvitation",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        guard let invitation = result as? [String: Any] else {
            throw ClientError.apiError(detail: "Invalid invitation response")
        }
        return invitation
    }
}

struct AcceptMomentInvitation: CloudFunction {

    typealias ReturnType = [String: Any]

    let momentId: String

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> [String: Any] {
        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: ["momentId": self.momentId],
            callName: "acceptMomentInvitation",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        guard let invitation = result as? [String: Any] else {
            throw ClientError.apiError(detail: "Invalid Moment invitation response")
        }
        return invitation
    }
}

struct GetAppClipShareContext: CloudFunction {

    typealias ReturnType = [String: Any]

    enum Kind: String {
        case invite
        case moment
    }

    let kind: Kind
    let id: String

    func makeRequest(
        andUpdate statusables: [Statusable] = [],
        viewsToIgnore: [UIView] = []
    ) async throws -> [String: Any] {
        let result = try await self.makeRequest(
            andUpdate: statusables,
            params: ["kind": self.kind.rawValue, "id": self.id],
            callName: "getAppClipShareContext",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
        guard let context = result as? [String: Any] else {
            throw ClientError.apiError(detail: "Invalid App Clip share context")
        }
        return context
    }
}

struct RespondToReservationInvitation: CloudFunction {

    enum Decision: String {
        case accepted
        case declined
    }

    typealias ReturnType = Any

    let reservationId: String
    let decision: Decision

    func makeRequest(andUpdate statusables: [Statusable] = [],
                     viewsToIgnore: [UIView] = []) async throws -> Any {
        let params = ["reservationId": self.reservationId,
                      "decision": self.decision.rawValue]

        return try await self.makeRequest(
            andUpdate: statusables,
            params: params,
            callName: "respondToReservationInvitation",
            delayInterval: 0.0,
            viewsToIgnore: viewsToIgnore
        )
    }
}
