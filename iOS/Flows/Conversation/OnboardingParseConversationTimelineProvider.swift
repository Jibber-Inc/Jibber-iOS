//
//  OnboardingParseConversationTimelineProvider.swift
//  Jibber
//

import Combine
import Foundation
import ParseCore

/// Bridges the canonical onboarding conversation into the same Parse-backed
/// controller used by the production conversation surface. Temporary pre-auth
/// entries remain visible until the first authoritative message page arrives,
/// and stable client message identifiers reconcile those entries in place.
@MainActor
final class OnboardingParseConversationTimelineProvider: ConversationTimelineProviding {

    private(set) var timelineEntries: [ConversationTimelineEntry]
    var didChange: CompletionOptional = nil

    let conversationController: ParseConversationController

    private var temporaryEntriesByID: [String: ConversationTimelineEntry]
    private var subscriptions = Set<AnyCancellable>()
    private var synchronizationTask: Task<Void, Never>?

    init(
        conversationId: String,
        temporaryEntries: [ConversationTimelineEntry]
    ) {
        self.conversationController = ParseConversationController.controller(
            for: conversationId
        )
        self.timelineEntries = temporaryEntries
        self.temporaryEntriesByID = Dictionary(
            uniqueKeysWithValues: temporaryEntries.map { ($0.id, $0) }
        )

        self.conversationController.messagesChangesPublisher
            .mainSink { [weak self] _ in
                self?.refreshFromParseController()
            }
            .store(in: &self.subscriptions)

        self.synchronizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.initializeMessagingIfNeeded()
                try await self.conversationController.synchronize()
            } catch is CancellationError {
                return
            } catch {
                logError(error)
            }
            self.refreshFromParseController()
        }
    }

    deinit {
        self.synchronizationTask?.cancel()
    }

    /// Refreshes the temporary side of the bridge after an explicit onboarding
    /// sync. Parse remains authoritative as soon as it has a matching message.
    func updateTemporaryEntries(_ entries: [ConversationTimelineEntry]) {
        self.temporaryEntriesByID = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.id, $0) }
        )
        self.refreshFromParseController(forceTemporaryRefresh: true)
    }

    func synchronize() async {
        do {
            try await self.initializeMessagingIfNeeded()
            try await self.conversationController.synchronize()
        } catch is CancellationError {
            return
        } catch {
            logError(error)
        }
        self.refreshFromParseController()
    }

    private func initializeMessagingIfNeeded() async throws {
        guard !ParseMessagingManager.shared.isInitialized else { return }
        guard let user = User.current() else {
            throw ParseMessagingManagerError.missingUserID
        }
        try await ParseMessagingManager.shared.initialize(for: user)
    }

    private func refreshFromParseController(
        forceTemporaryRefresh: Bool = false
    ) {
        let persistedMessages = self.conversationController.messages
            .filter { !$0.isDeleted }
            .reversed()

        var lastProgressOrdinal: Int?
        var persistedEntries: [ConversationTimelineEntry] = []
        persistedEntries.reserveCapacity(persistedMessages.count)

        for message in persistedMessages {
            let explicitStep = (message.attributes?["onboardingStep"] as? String)
                .flatMap(OnboardingStepID.init(rawValue:))
            if let explicitStep {
                lastProgressOrdinal = explicitStep.timelineOrdinal
            }
            persistedEntries.append(
                ConversationTimelineEntry(
                    message: message,
                    progressOrdinal: lastProgressOrdinal
                )
            )
        }

        let persistedIDs = Set(persistedEntries.map(\.id))
        let unresolvedTemporaryEntries = self.temporaryEntriesByID.values.filter {
            !persistedIDs.contains($0.id)
        }
        let reconciledEntries = (unresolvedTemporaryEntries + persistedEntries).sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return $0.date < $1.date
        }

        guard ConversationTimelineRefreshPolicy.shouldApply(
            currentIDs: self.timelineEntries.map(\.id),
            nextIDs: reconciledEntries.map(\.id),
            containsPersistedEntries: !persistedEntries.isEmpty,
            forcesContentRefresh: forceTemporaryRefresh
        ) else {
            return
        }
        self.timelineEntries = reconciledEntries
        self.didChange?()
    }
}
