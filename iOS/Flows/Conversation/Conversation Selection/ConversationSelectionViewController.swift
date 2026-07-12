//
//  ConversationSelectionViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/20/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Combine
import Foundation
import MessagingContracts

class ConversationSelectionViewController: DiffableCollectionViewController<ConversationSelectionDataSource.SectionType,
                                           ConversationSelectionDataSource.ItemType,
                                           ConversationSelectionDataSource> {

    private static let conversationPageSize = 20
    
    private let topGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor,
                                                                 ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                          startPoint: .topCenter,
                                                          endPoint: .bottomCenter)
    
    private let titleLabel = ThemeLabel(font: .mediumBold)
    
    private(set) var conversationListController: ParseConversationListController?
    private var conversationListChangesCancellable: AnyCancellable?
    private var loadNextConversationsTask: Task<Void, Never>?
    private var isInitialConversationSnapshotApplied = false
    
    init() {
        super.init(with: ConversationSelectionCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.collectionView.allowsMultipleSelection = false
        self.loadInitialData()
        
        self.view.addSubview(self.topGradientView)
        self.view.addSubview(self.titleLabel)
        self.titleLabel.setText("Choose")
        self.titleLabel.textAlignment = .center
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.topGradientView.expandToSuperviewWidth()
        self.topGradientView.height = 80
        self.topGradientView.pin(.top)
        
        self.titleLabel.setSize(withWidth: Theme.getPaddedWidth(with: self.view.width))
        self.titleLabel.pinToSafeAreaTop()
        self.titleLabel.centerOnX()
    }
    
    override func getAllSections() -> [ConversationSelectionDataSource.SectionType] {
        return ConversationSelectionDataSource.SectionType.allCases
    }

    override func collectionViewDataWasLoaded() {
        super.collectionViewDataWasLoaded()
        self.isInitialConversationSnapshotApplied = true
    }
    
    override func retrieveDataForSnapshot() async -> [ConversationSelectionDataSource.SectionType : [ConversationSelectionDataSource.ItemType]] {
        var data: [ConversationSelectionDataSource.SectionType: [ConversationSelectionDataSource.ItemType]] = [:]

        guard let currentUserID = User.current()?.objectId else { return data }

        let controller = self.makeConversationListController()
        do {
            try await controller.synchronize(pageSize: Self.conversationPageSize)
            try await self.loadEnoughEligibleConversations(
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
    ) -> [ConversationSelectionDataSource.ItemType] {
        conversations
            .filter { conversation in
                conversation.kind != .moment
                    && conversation.memberCount > 1
                    && conversation.activeMembers.contains { $0.userID == currentUserID }
            }
            .map { .conversation($0.id) }
    }

    @MainActor
    private func applyConversationSnapshot(currentUserID: String) async {
        let items = self.items(
            from: self.conversationListController?.conversations ?? [],
            currentUserID: currentUserID
        )
        var snapshot = self.dataSource.snapshot()
        snapshot.setItems(items, in: .conversations)
        await self.dataSource.apply(snapshot)
    }

    private func loadEnoughEligibleConversations(
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
