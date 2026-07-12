//
//  ConversationsViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/9/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Combine
import Foundation
import MessagingContracts

class ConversationsViewController: DiffableCollectionViewController<ConversationsDataSource.SectionType,
                                   ConversationsDataSource.ItemType,
                                   ConversationsDataSource>, HomeContentType {

    private static let conversationPageSize = 20
    
    var contentTitle: String {
        return "Conversations"
    }
    
    private(set) var conversationListController: ParseConversationListController?
    private var conversationListChangesCancellable: AnyCancellable?
    private var loadNextConversationsTask: Task<Void, Never>?
    private var isInitialConversationSnapshotApplied = false
    
    private lazy var refreshControl: UIRefreshControl = {
        let action = UIAction { [unowned self] _ in
            self.startLoadAllTask()
        }
        let control = UIRefreshControl(frame: .zero, primaryAction: action)
        control.tintColor = ThemeColor.white.color
        return control
    }()
    
    init() {
        super.init(with: ConversationsCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.loadInitialData()
        self.collectionView.allowsMultipleSelection = false
        self.collectionView.refreshControl = self.refreshControl
    }
    
    override func getAllSections() -> [ConversationsDataSource.SectionType] {
        return ConversationsDataSource.SectionType.allCases
    }

    override func collectionViewDataWasLoaded() {
        super.collectionViewDataWasLoaded()
        self.isInitialConversationSnapshotApplied = true
    }
    
    override func retrieveDataForSnapshot() async -> [ConversationsDataSource.SectionType : [ConversationsDataSource.ItemType]] {
        var data: [ConversationsDataSource.SectionType: [ConversationsDataSource.ItemType]] = [:]

        guard let currentUserID = User.current()?.objectId else { return data }

        let controller = self.makeConversationListController()
        do {
            try await controller.synchronize(pageSize: Self.conversationPageSize)
            try await self.loadEnoughVisibleConversations(
                with: controller,
                currentUserID: currentUserID
            )
        } catch {
            logError(error)
        }

        data[.conversations] = self.items(
            from: controller.conversations,
            currentUserID: currentUserID
        )
        
        return data
    }
    
    // MARK: - Conversation Loading
    
    /// The currently running task that is loading conversations.
    private var loadConversationsTask: Task<Void, Never>?
    
    private func startLoadAllTask() {
        self.loadConversationsTask?.cancel()

        self.loadConversationsTask = Task { @MainActor [weak self] in
            guard let self,
                  let currentUserID = User.current()?.objectId else { return }

            let controller = self.makeConversationListController()
            do {
                try await controller.synchronize(pageSize: Self.conversationPageSize)
                try await self.loadEnoughVisibleConversations(
                    with: controller,
                    currentUserID: currentUserID
                )
            } catch {
                logError(error)
            }

            guard !Task.isCancelled else { return }
            await self.applyConversationSnapshot(
                currentUserID: currentUserID,
                endsRefreshing: true
            )
        }.add(to: self.autocancelTaskPool)
    }

    @MainActor
    private func applyConversationSnapshot(
        currentUserID: String,
        endsRefreshing: Bool = false
    ) async {
        let items = self.items(
            from: self.conversationListController?.conversations ?? [],
            currentUserID: currentUserID
        )
        var snapshot = self.dataSource.snapshot()
        snapshot.setItems(items, in: .conversations)

        await self.dataSource.apply(snapshot)

        if endsRefreshing, self.refreshControl.isRefreshing {
            self.refreshControl.endRefreshing()
        }
    }

    private func makeConversationListController() -> ParseConversationListController {
        if let controller = self.conversationListController {
            return controller
        }

        let controller = ParseConversationListController(automaticallySynchronize: false)
        self.conversationListController = controller
        self.conversationListChangesCancellable = controller.conversationsChangesPublisher
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isInitialConversationSnapshotApplied,
                          let currentUserID = User.current()?.objectId else { return }
                    await self.applyConversationSnapshot(currentUserID: currentUserID)
                }
            }
        return controller
    }

    private func items(
        from conversations: [ParseConversation],
        currentUserID: String
    ) -> [ConversationsDataSource.ItemType] {
        conversations
            .filter { conversation in
                conversation.kind != .moment
                    && conversation.activeMembers.contains { $0.userID == currentUserID }
                    && conversation.latestMessages.contains { !$0.isDeleted }
            }
            .map { .conversation($0.id) }
    }

    private func loadEnoughVisibleConversations(
        with controller: ParseConversationListController,
        currentUserID: String
    ) async throws {
        while self.items(
            from: controller.conversations,
            currentUserID: currentUserID
        ).count < Self.conversationPageSize,
              !controller.hasLoadedAllConversations,
              !Task.isCancelled {
            try await controller.loadNextConversations(limit: Self.conversationPageSize)
        }
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        super.collectionView(collectionView, willDisplay: cell, forItemAt: indexPath)

        guard indexPath.item >= collectionView.numberOfItems(inSection: indexPath.section) - 2,
              self.loadNextConversationsTask == nil,
              let controller = self.conversationListController,
              !controller.hasLoadedAllConversations,
              let currentUserID = User.current()?.objectId else { return }

        self.loadNextConversationsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.loadNextConversationsTask = nil }

            let previousCount = self.items(
                from: controller.conversations,
                currentUserID: currentUserID
            ).count
            do {
                repeat {
                    try await controller.loadNextConversations(limit: Self.conversationPageSize)
                } while self.items(
                    from: controller.conversations,
                    currentUserID: currentUserID
                ).count == previousCount && !controller.hasLoadedAllConversations
            } catch {
                logError(error)
            }

            guard !Task.isCancelled else { return }
            await self.applyConversationSnapshot(currentUserID: currentUserID)
        }.add(to: self.autocancelTaskPool)
    }
}
