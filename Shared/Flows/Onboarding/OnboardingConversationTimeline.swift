//
//  OnboardingConversationTimeline.swift
//  Jibber
//

import Foundation
import MessagingContracts
import ParseCore

/// A lightweight `Messageable` used before Parse authentication and by the App Clip's
/// authenticated transcript adapter. Its stable client id is the same id used by Cloud
/// Code, allowing the shared Time Machine to reconcile in place after verification.
struct OnboardingTimelineMessage: Messageable {
    let id: String
    let conversationId: String
    let createdAt: Date
    let isFromCurrentUser: Bool
    let authorId: String
    let attributes: [String: Any]?
    let person: PersonType?
    let deliveryStatus: DeliveryStatus = .read
    let deliveryType: MessageDeliveryType = .respectful
    let kind: MessageKind
    let isDeleted: Bool = false
    let totalReplyCount: Int = 0
    let recentReplies: [Messageable] = []
    let lastUpdatedAt: Date?
    let expressions: [ExpressionInfo] = []

    var canBeConsumed: Bool { false }
    var isConsumedByMe: Bool { true }
    var isConsumed: Bool { true }
    var hasBeenConsumedBy: [PersonType] { [] }

    init(
        id: String,
        conversationId: String,
        createdAt: Date,
        isFromCurrentUser: Bool,
        authorId: String,
        text: String,
        person: PersonType?,
        step: OnboardingStepID,
        revision: Int,
        automated: Bool
    ) {
        self.id = id
        self.conversationId = conversationId
        self.createdAt = createdAt
        self.isFromCurrentUser = isFromCurrentUser
        self.authorId = authorId
        self.person = person
        self.kind = .text(text)
        self.lastUpdatedAt = createdAt
        self.attributes = [
            "surface": "onboarding",
            "onboardingStep": step.rawValue,
            "copyRevision": revision,
            "automated": automated
        ]
    }

    func setToConsumed() async {}
    func setToUnconsumed() async throws {}
}

/// Owns the provider-neutral transcript presented by the shared conversation surface.
/// All mutation is on the main actor because its consumer is a diffable UIKit datasource.
@MainActor
final class OnboardingConversationTimelineStore: ConversationTimelineProviding {
    private(set) var timelineEntries: [ConversationTimelineEntry] = []
    private var persistedTurnIDs: Set<String> = []
    private var persistedAutomatedSteps: Set<OnboardingStepID> = []

    private(set) var conversationId: String = "onboarding-preauth"
    private(set) var guide: PersonType?
    private(set) var guideUserId: String = "onboarding-guide"
    private(set) var messagingRevision: Int = 0

    func configureGuide(
        _ guide: PersonType?,
        guideUserId: String? = nil,
        conversationId: String? = nil,
        messagingRevision: Int? = nil
    ) {
        self.guide = guide
        if let guideUserId, !guideUserId.isEmpty {
            self.guideUserId = guideUserId
        }
        if let conversationId, !conversationId.isEmpty {
            self.conversationId = conversationId
        }
        if let messagingRevision {
            self.messagingRevision = messagingRevision
        }
    }

    func upsertLocalPrompt(
        step: OnboardingStepID,
        text: String,
        revision: Int,
        createdAt: Date = Date()
    ) {
        let id = Self.promptID(revision: revision, step: step)
        // Once the backend has supplied this stable turn, it owns both the
        // locked copy and timestamp. Dynamic local copy must never replace it.
        guard !self.persistedTurnIDs.contains(id),
              !self.persistedAutomatedSteps.contains(step) else { return }
        let stableCreatedAt = self.timelineEntries.first(where: { $0.id == id })?.date
            ?? createdAt
        let message = OnboardingTimelineMessage(
            id: id,
            conversationId: self.conversationId,
            createdAt: stableCreatedAt,
            isFromCurrentUser: false,
            authorId: self.guideUserId,
            text: text,
            person: self.guide,
            step: step,
            revision: revision,
            automated: true
        )
        self.upsert(
            ConversationTimelineEntry(
                id: id,
                date: stableCreatedAt,
                message: message,
                progressOrdinal: step.timelineOrdinal
            )
        )
    }

    /// Reconciles the temporary transcript with persisted backend messages. Empty server
    /// responses do not clear the visible pre-auth history during transient rollout errors.
    func reconcile(
        with turns: [OnboardingConversationTurn],
        session: OnboardingConversationSession
    ) {
        if let conversationId = session.conversationId, !conversationId.isEmpty {
            self.conversationId = conversationId
        }
        if let guideUserId = session.guideUserId, !guideUserId.isEmpty {
            self.guideUserId = guideUserId
        }
        if let revision = session.messagingRevision {
            self.messagingRevision = revision
        }
        guard !turns.isEmpty else { return }

        let currentUserID = User.current()?.objectId
        let parsedTurns = turns.compactMap { turn -> ConversationTimelineEntry? in
            guard !turn.id.isEmpty,
                  let step = turn.metadata.onboardingStep else { return nil }

            let authorID = turn.authorId ?? self.guideUserId
            let isFromCurrentUser = currentUserID != nil && authorID == currentUserID
            let person: PersonType? = isFromCurrentUser ? User.current() : self.guide
            let createdAt = Self.parseDate(turn.createdAt) ?? Date()
            let message = OnboardingTimelineMessage(
                id: turn.id,
                conversationId: self.conversationId,
                createdAt: createdAt,
                isFromCurrentUser: isFromCurrentUser,
                authorId: authorID,
                text: turn.text,
                person: person,
                step: step,
                revision: turn.metadata.copyRevision ?? self.messagingRevision,
                automated: turn.metadata.automated
            )
            return ConversationTimelineEntry(
                id: turn.id,
                date: createdAt,
                message: message,
                progressOrdinal: step.timelineOrdinal
            )
        }
        guard !parsedTurns.isEmpty else { return }
        self.persistedTurnIDs.formUnion(parsedTurns.map(\.id))
        self.persistedAutomatedSteps.formUnion(
            turns.compactMap { turn in
                turn.metadata.automated ? turn.metadata.onboardingStep : nil
            }
        )
        self.timelineEntries = parsedTurns.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.id < rhs.id }
            return lhs.date < rhs.date
        }
    }

    func entry(for step: OnboardingStepID) -> ConversationTimelineEntry? {
        self.timelineEntries.last { entry in
            (entry.message.attributes?["onboardingStep"] as? String) == step.rawValue
        }
    }

    func step(for entry: ConversationTimelineEntry) -> OnboardingStepID? {
        guard let value = entry.message.attributes?["onboardingStep"] as? String else {
            return nil
        }
        return OnboardingStepID(rawValue: value)
    }

    /// Maps raw message position through per-message step metadata. This remains correct
    /// when a step gains multiple server-authored turns in a later copy revision.
    func progress(at continuousPosition: CGFloat) -> CGFloat {
        guard !self.timelineEntries.isEmpty else { return 1 }

        let clampedPosition = clamp(
            continuousPosition,
            0,
            CGFloat(max(0, self.timelineEntries.count - 1))
        )
        let lowerIndex = Int(floor(clampedPosition))
        let upperIndex = min(self.timelineEntries.count - 1, lowerIndex + 1)
        let fraction = clampedPosition - CGFloat(lowerIndex)
        let lower = CGFloat(self.timelineEntries[lowerIndex].progressOrdinal ?? 0)
        let upper = CGFloat(self.timelineEntries[upperIndex].progressOrdinal ?? Int(lower))
        let ordinal = lower + ((upper - lower) * fraction)
        // Welcome is a real first step, so the surface always begins with one
        // completed segment rather than exposing a zero-percent state.
        return clamp(ordinal + 1, 1, 5)
    }

    private func upsert(_ entry: ConversationTimelineEntry) {
        if let index = self.timelineEntries.firstIndex(where: { $0.id == entry.id }) {
            self.timelineEntries[index] = entry
        } else {
            self.timelineEntries.append(entry)
        }
        self.timelineEntries.sort { lhs, rhs in
            let leftOrdinal = lhs.progressOrdinal ?? 0
            let rightOrdinal = rhs.progressOrdinal ?? 0
            if leftOrdinal == rightOrdinal { return lhs.date < rhs.date }
            return leftOrdinal < rightOrdinal
        }
    }

    private static func promptID(revision: Int, step: OnboardingStepID) -> String {
        "onboarding:\(revision):\(step.rawValue):prompt"
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

extension OnboardingStepID {
    var timelineOrdinal: Int {
        switch self {
        case .welcome:
            return 0
        case .phone:
            return 1
        case .verification:
            return 2
        case .name:
            return 3
        case .faceCapture:
            return 4
        case .completed:
            return 5
        }
    }
}
