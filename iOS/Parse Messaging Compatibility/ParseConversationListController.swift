//
//  ParseConversationListController.swift
//  Jibber
//

import Combine
import Foundation
import MessagingContracts

@MainActor
final class ParseConversationListController: Hashable {

    @Published private(set) var conversations: [ParseConversation] = []
    private(set) var hasLoadedAllConversations = false

    private let manager: ParseMessagingManager
    private let includesHiddenConversations: Bool
    private let listChangesSubject = PassthroughSubject<[ParseListChange<ParseConversation>], Never>()
    private var snapshots: [MessagingConversationSnapshot] = []
    private var nextCursor: MessagingCursor?
    private var messagingChangeCancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

    init(
        manager: ParseMessagingManager,
        includesHiddenConversations: Bool = false,
        automaticallySynchronize: Bool = true
    ) {
        self.manager = manager
        self.includesHiddenConversations = includesHiddenConversations
        self.observeMessagingChanges()
        if automaticallySynchronize {
            self.refreshTask = Task { @MainActor [weak self] in
                do {
                    try await self?.synchronize()
                } catch {
                    logError(error)
                }
            }
        }
    }

    convenience init(
        includesHiddenConversations: Bool = false,
        automaticallySynchronize: Bool = true
    ) {
        self.init(
            manager: .shared,
            includesHiddenConversations: includesHiddenConversations,
            automaticallySynchronize: automaticallySynchronize
        )
    }

    deinit {
        self.refreshTask?.cancel()
    }

    var conversationsChangesPublisher: AnyPublisher<[ParseListChange<ParseConversation>], Never> {
        self.listChangesSubject.eraseToAnyPublisher()
    }

    func conversationController(for conversationID: String) -> ParseConversationController {
        ParseConversationController(
            conversationID: conversationID,
            manager: self.manager
        )
    }

    func synchronize(pageSize: Int = 50) async throws {
        try self.applyCachedState(pageSize: pageSize)
        let page = try await self.manager.conversations(pageSize: pageSize)
        self.snapshots = self.merge(self.snapshots, with: page.items)
        self.nextCursor = page.nextCursor
        self.hasLoadedAllConversations = !page.hasMore
        await self.refreshMembers(for: page.items)
        try self.applyCachedState(pageSize: max(pageSize, self.snapshots.count + 1))
    }

    func loadNextConversations(limit: Int? = nil) async throws {
        guard !self.hasLoadedAllConversations else { return }
        let page = try await self.manager.conversations(
            before: self.nextCursor,
            pageSize: limit ?? 25
        )
        self.snapshots = self.merge(self.snapshots, with: page.items)
        self.nextCursor = page.nextCursor
        self.hasLoadedAllConversations = !page.hasMore
        await self.refreshMembers(for: page.items)
        try self.publishConversations()
    }

    @discardableResult
    func createConversation(
        memberIDs: [String],
        type: MessagingConversationKind,
        title: String? = nil,
        clientConversationID: String = UUID().uuidString.lowercased(),
        contextKey: String? = nil
    ) async throws -> ParseConversationController {
        let snapshot = try await self.manager.createConversation(
            memberIDs: memberIDs,
            type: type,
            title: title,
            clientConversationID: clientConversationID,
            contextKey: contextKey
        )
        self.snapshots = self.merge(self.snapshots, with: [snapshot])
        _ = try? await self.manager.members(conversationID: snapshot.id)
        try self.publishConversations()
        return ParseConversationController(
            conversationID: snapshot.id,
            manager: self.manager
        )
    }

    /// Creates or recovers the one comments conversation for a Moment and
    /// stores the Parse conversation id on the Moment. `commentsId` remains the
    /// read-only transitional fallback for older Moment objects.
    @discardableResult
    func createConversation(
        for moment: Moment,
        memberIDs: [String]
    ) async throws -> ParseConversationController {
        guard let momentID = moment.objectId else {
            throw ParseMessagingCompatibilityError.invalidConversationID
        }
        let controller = try await self.createConversation(
            memberIDs: memberIDs,
            type: .moment,
            contextKey: "moment:\(momentID)"
        )
        if moment.messagingConversationId != controller.conversationID.rawValue {
            moment.messagingConversationId = controller.conversationID.rawValue
            _ = try await moment.saveToServer()
        }
        return controller
    }

    private func observeMessagingChanges() {
        self.messagingChangeCancellable = NotificationCenter.default
            .publisher(for: .parseMessagingDidChange, object: self.manager)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    do {
                        try self.applyCachedState(pageSize: max(50, self.snapshots.count + 10))
                    } catch {
                        logError(error)
                    }
                }
            }
    }

    private func applyCachedState(pageSize: Int) throws {
        guard let store = self.manager.store else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        let page = try store.cachedConversations(before: nil, pageSize: pageSize)
        self.snapshots = page.items
        self.nextCursor = page.nextCursor
        self.hasLoadedAllConversations = !page.hasMore
        try self.publishConversations()
    }

    private func publishConversations() throws {
        guard let store = self.manager.store else {
            throw ParseMessagingCompatibilityError.messagingNotInitialized
        }
        var values: [ParseConversation] = []
        for snapshot in self.snapshots where !snapshot.isDeleted {
            let members = try store.cachedMembers(conversationID: snapshot.id)
                .map(ParseConversationMember.init)
            if !self.includesHiddenConversations,
               members.first(where: \.isCurrentUser)?.isHidden == true {
                continue
            }
            let latest = try store.cachedMessages(
                conversationID: snapshot.id,
                before: nil,
                pageSize: 1
            ).items.map { ParseMessage(snapshot: $0) }
            values.append(
                ParseConversation(snapshot: snapshot, members: members, messages: latest)
            )
        }
        values.sort {
            if $0.snapshot.lastActivityAt == $1.snapshot.lastActivityAt {
                return $0.id > $1.id
            }
            return $0.snapshot.lastActivityAt > $1.snapshot.lastActivityAt
        }

        let changes = ParseListDiffer.changes(
            from: self.conversations,
            to: values,
            identifiedBy: { $0.id },
            valuesEqual: ==
        )
        self.conversations = values
        if !changes.isEmpty {
            self.listChangesSubject.send(changes)
        }
    }

    private func refreshMembers(for conversations: [MessagingConversationSnapshot]) async {
        // The conversation endpoint intentionally does not duplicate membership
        // state. Hydrate the visible page in one query, then LiveQuery keeps it fresh.
        _ = try? await self.manager.members(conversationIDs: conversations.map(\.id))
    }

    private func merge(
        _ existing: [MessagingConversationSnapshot],
        with incoming: [MessagingConversationSnapshot]
    ) -> [MessagingConversationSnapshot] {
        var values = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for snapshot in incoming {
            values[snapshot.id] = snapshot
        }
        return values.values.sorted {
            if $0.lastActivityAt == $1.lastActivityAt { return $0.id > $1.id }
            return $0.lastActivityAt > $1.lastActivityAt
        }
    }

    nonisolated static func == (
        lhs: ParseConversationListController,
        rhs: ParseConversationListController
    ) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
