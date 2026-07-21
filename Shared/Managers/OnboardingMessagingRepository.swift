//
//  OnboardingMessagingRepository.swift
//  Jibber
//

import Foundation
import ParseCore

/// Owns the latest validated onboarding copy. Capture `snapshot` once when an
/// onboarding coordinator starts so a remote refresh cannot change copy during
/// an in-progress session.
@MainActor
final class OnboardingMessagingRepository {
    static let shared = OnboardingMessagingRepository()

    nonisolated static let parseConfigKey = onboardingMessagingConfigKey
    nonisolated static let cacheKey = "onboardingMessaging.lastKnownGood.v1"
    nonisolated static let revisionCacheKeyPrefix =
        "onboardingMessaging.revision.v1."

    private let defaults: UserDefaults?
    private let fallbackDocument: OnboardingMessagingDocument
    private let fallbackSource: OnboardingMessagingSource

    private(set) var snapshot: OnboardingMessaging
    private var snapshotsByRevision: [Int: OnboardingMessaging] = [:]

    private init() {
        let bundle = Bundle(for: Config.self)
        let bundled = Self.loadBundledFallback(from: bundle)
        let fallback = bundled ?? .emergencyFallback
        let fallbackSource: OnboardingMessagingSource = bundled == nil ? .emergency : .bundled
        let defaults = UserDefaults(suiteName: Config.shared.environment.groupId)
        let cached = Self.loadCachedDocument(from: defaults)

        let resolution = try? OnboardingMessagingResolver.resolve(
            remote: nil,
            cached: cached,
            fallback: fallback
        )
        let selectedDocument = resolution?.document ?? .emergencyFallback
        let selectedSource: OnboardingMessagingSource
        if resolution?.source == .cache {
            selectedSource = .cache
        } else {
            selectedSource = fallbackSource
        }

        self.defaults = defaults
        self.fallbackDocument = fallback
        self.fallbackSource = fallbackSource
        let snapshot = try! OnboardingMessaging(
            document: selectedDocument,
            source: selectedSource
        )
        self.snapshot = snapshot
        self.snapshotsByRevision[snapshot.revision] = snapshot
        if let data = try? selectedDocument.validatedData() {
            // Backfill the revision-addressed cache when upgrading from the
            // legacy single latest-document key so an already locked session
            // can still restore this copy on its next launch.
            self.defaults?.set(
                data,
                forKey: Self.revisionCacheKey(snapshot.revision)
            )
        }

        if let fallbackSnapshot = try? OnboardingMessaging(
            document: fallback,
            source: fallbackSource
        ) {
            self.snapshotsByRevision[fallbackSnapshot.revision] = fallbackSnapshot
        }
    }

    /// Applies the fetched Parse Config document when it is valid and newer
    /// than the last-known-good revision. Failure is deliberately non-fatal:
    /// onboarding continues with cache or bundled copy.
    func prepare(with config: PFConfig?) {
        let remote = Self.decodeRemoteDocument(config?.onboardingMessagingJSONObject)
        let cached = Self.loadCachedDocument(from: self.defaults)

        guard let resolution = try? OnboardingMessagingResolver.resolve(
            remote: remote,
            cached: cached,
            fallback: self.fallbackDocument
        ) else {
            return
        }

        let source = resolution.source == .bundled
            ? self.fallbackSource
            : resolution.source
        guard let resolvedSnapshot = try? OnboardingMessaging(
            document: resolution.document,
            source: source
        ) else {
            return
        }

        self.snapshot = resolvedSnapshot
        self.snapshotsByRevision[resolvedSnapshot.revision] = resolvedSnapshot

        if resolution.source == .remote,
           let data = try? resolution.document.validatedData() {
            self.defaults?.set(data, forKey: Self.cacheKey)
            self.defaults?.set(
                data,
                forKey: Self.revisionCacheKey(resolvedSnapshot.revision)
            )
        }
    }

    func sessionSnapshot() -> OnboardingMessaging {
        self.snapshot
    }

    /// Resolves the exact document revision locked into an OnboardingSession.
    /// Older installs may only have the legacy latest-document cache; callers
    /// intentionally fall back to their current snapshot when the exact
    /// revision is unavailable rather than silently relabeling newer copy.
    func sessionSnapshot(forRevision revision: Int) -> OnboardingMessaging? {
        if let snapshot = self.snapshotsByRevision[revision] {
            return snapshot
        }

        guard let document = Self.loadCachedDocument(
            from: self.defaults,
            key: Self.revisionCacheKey(revision)
        ),
        document.revision == revision,
        let snapshot = try? OnboardingMessaging(
            document: document,
            source: .cache
        ) else {
            return nil
        }

        self.snapshotsByRevision[revision] = snapshot
        return snapshot
    }

    /// Validates and installs the server-pinned document carried by an
    /// OnboardingSession. This closes the fresh-device gap where no historical
    /// revision has ever existed in local Parse Config cache.
    func sessionSnapshot(
        documentJSON: String,
        expectedRevision: Int
    ) -> OnboardingMessaging? {
        guard let data = documentJSON.data(using: .utf8),
              let document = try? OnboardingMessagingDocument.decode(from: data),
              document.revision == expectedRevision,
              let snapshot = try? OnboardingMessaging(
                document: document,
                source: .cache
              ),
              let validatedData = try? document.validatedData() else {
            return nil
        }

        self.snapshotsByRevision[expectedRevision] = snapshot
        self.defaults?.set(
            validatedData,
            forKey: Self.revisionCacheKey(expectedRevision)
        )
        return snapshot
    }

    /// Parse Config stores this payload as a JSON string because localized copy
    /// keys contain dots, which cannot safely be represented as nested Mongo
    /// object keys. Accept an object as well for backwards-compatible fixtures.
    nonisolated static func decodeRemoteDocument(
        _ value: Any?
    ) -> OnboardingMessagingDocument? {
        if let json = value as? String,
           let data = json.data(using: .utf8) {
            return try? OnboardingMessagingDocument.decode(from: data)
        }

        guard let value else { return nil }
        return try? OnboardingMessagingDocument.decode(jsonObject: value)
    }

    nonisolated static func loadBundledFallback(
        from bundle: Bundle
    ) -> OnboardingMessagingDocument? {
        guard let url = bundle.url(
            forResource: "OnboardingMessagingFallback",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? OnboardingMessagingDocument.decode(from: data)
    }

    nonisolated private static func loadCachedDocument(
        from defaults: UserDefaults?,
        key: String = OnboardingMessagingRepository.cacheKey
    ) -> OnboardingMessagingDocument? {
        guard let data = defaults?.data(forKey: key) else {
            return nil
        }
        return try? OnboardingMessagingDocument.decode(from: data)
    }

    nonisolated private static func revisionCacheKey(_ revision: Int) -> String {
        Self.revisionCacheKeyPrefix + String(revision)
    }
}
