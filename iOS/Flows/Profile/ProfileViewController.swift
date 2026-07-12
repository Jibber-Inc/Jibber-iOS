//
//  UserProfileViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/22/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Combine
import Foundation
import MessagingContracts

class ProfileViewController: DiffableCollectionViewController<ProfileDataSource.SectionType,
                             ProfileDataSource.ItemType,
                             ProfileDataSource> {

    private static let conversationPageSize = 20
    
    private var person: PersonType
    
    lazy var header = ProfileHeaderView()
    lazy var contextCuesVC = ContextCuesViewController(person: self.person)
    private let contextCueHeaderLabel = ThemeLabel(font: .regular)
    
    private let segmentGradientView = GradientPassThroughView(with: [ThemeColor.B6.color.cgColor,
                                                         ThemeColor.B6.color.cgColor,
                                                         ThemeColor.B6.color.cgColor,
                                                         ThemeColor.B6.color.withAlphaComponent(0.0).cgColor],
                                                  startPoint: .topCenter,
                                                  endPoint: .bottomCenter)
    private let backgroundView = BaseView()
    lazy var segmentControl = ProfileSegmentControl()
    
    private(set) var conversationListController: ParseConversationListController?
    private var conversationListChangesCancellable: AnyCancellable?
    private var loadNextConversationsTask: Task<Void, Never>?
    
    private let bottomGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor, ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                  startPoint: .bottomCenter,
                                                  endPoint: .topCenter)
    
    private let darkBlurView = DarkBlurView()
            
    init(with person: PersonType) {
        self.person = person
        super.init(with: ProfileCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.modalPresentationStyle = .popover
        if let pop = self.popoverPresentationController {
            let sheet = pop.adaptiveSheetPresentationController
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        
        self.view.insertSubview(self.darkBlurView, belowSubview: self.collectionView)
                        
        self.view.addSubview(self.header)
        
        self.addChild(viewController: self.contextCuesVC, toView: self.view)
        
        self.view.addSubview(self.contextCueHeaderLabel)
        self.contextCueHeaderLabel.setText("My Vibes...")
        
        self.view.addSubview(self.bottomGradientView)
        
        self.backgroundView.set(backgroundColor: .B6)
        self.backgroundView.layer.cornerRadius = Theme.cornerRadius
        self.backgroundView.layer.masksToBounds = true
        self.backgroundView.clipsToBounds = true
        
        self.segmentGradientView.layer.cornerRadius = Theme.cornerRadius
        self.segmentGradientView.layer.masksToBounds = true
        self.segmentGradientView.clipsToBounds = true
        
        self.view.insertSubview(self.backgroundView, belowSubview: self.collectionView)
        self.view.insertSubview(self.segmentControl, aboveSubview: self.collectionView)
        self.view.insertSubview(self.segmentGradientView, belowSubview: self.segmentControl)
        
        self.segmentControl.didSelectSegmentIndex = { [unowned self] index in
            switch index {
            case .conversations:
                self.startLoadAllTask()
            case .moments:
                self.startLoadAllMoments()
            }
        }
        
        PeopleStore.shared
            .$personUpdated
            .filter { [unowned self] updatedPerson in
                // Only handle person updates related to the currently assigned person.
                self.person.personId ==  updatedPerson?.personId
            }.mainSink { [unowned self] person in
                guard let user = person as? User else { return }
                self.header.configure(with: user)
                self.contextCuesVC.reloadContextCues()
            }.store(in: &self.cancellables)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.collectionView.allowsMultipleSelection = false 
                
        Task { [unowned self] in
            guard let updatedPerson = await PeopleStore.shared.getPerson(withPersonId: self.person.personId) else {
                return
            }

            guard !Task.isCancelled else { return }

            self.person = updatedPerson

            self.header.configure(with: updatedPerson)
            self.loadInitialData()
            
            self.segmentControl.selectedSegmentIndex = 0
            self.startLoadAllMoments()

            self.view.setNeedsLayout()
        }.add(to: self.autocancelTaskPool)
    }
    
    override func willEnterForeground() {
        super.willEnterForeground()
        
        switch self.segmentControl.selectedSegmentIndex {
        case 0:
            self.startLoadAllMoments()
        case 1:
            self.startLoadAllTask()
        default:
            break
        }
    }
    
    override func viewDidLayoutSubviews() {
        self.header.expandToSuperviewWidth()
        self.header.height = ProfileHeaderView.height
        self.header.pin(.top, offset: .standard)
        
        self.contextCueHeaderLabel.setSize(withWidth: self.view.width)
        self.contextCueHeaderLabel.match(.top, to: .bottom, of: self.header, offset: .xtraLong)
        self.contextCueHeaderLabel.pin(.left, offset: .xtraLong)
        
        super.viewDidLayoutSubviews()
        
        self.darkBlurView.expandToSuperviewSize()
        self.darkBlurView.pin(.top, offset: .custom(48))
        self.darkBlurView.roundCorners()
        
        self.contextCuesVC.view.expandToSuperviewWidth()
        self.contextCuesVC.view.height = 44
        self.contextCuesVC.view.match(.top, to: .bottom, of: self.contextCueHeaderLabel, offset: .xtraLong)
        
        self.bottomGradientView.expandToSuperviewWidth()
        self.bottomGradientView.height = 94
        self.bottomGradientView.pin(.bottom)
        
        let padding = Theme.ContentOffset.xtraLong.value
        let totalWidth = self.collectionView.width - padding.doubled
        let multiplier = self.segmentControl.numberOfSegments < 3 ? 0.5 : 0.333
        let segmentWidth = totalWidth * multiplier
        self.segmentControl.sizeToFit()
        
        for index in 0...self.segmentControl.numberOfSegments - 1 {
            self.segmentControl.setWidth(segmentWidth, forSegmentAt: index)
        }

        self.segmentControl.width = self.collectionView.width - padding.doubled
        self.segmentControl.centerOnX()
        self.segmentControl.match(.top, to: .top, of: self.collectionView, offset: .xtraLong)
        
        self.backgroundView.frame = self.collectionView.frame
        self.backgroundView.height = self.collectionView.height + 100
        
        self.segmentGradientView.width = self.collectionView.width
        self.segmentGradientView.top = self.collectionView.top
        self.segmentGradientView.height = padding.doubled + self.segmentControl.height
        self.segmentGradientView.centerOnX()
    }
    
    override func layoutCollectionView(_ collectionView: UICollectionView) {
        self.collectionView.width = self.view.width - Theme.ContentOffset.xtraLong.value.doubled
        self.collectionView.match(.top, to: .bottom, of: self.contextCuesVC.view, offset: .custom(34))
        self.collectionView.height = self.view.height - self.contextCuesVC.view.bottom - 34
        self.collectionView.centerOnX()
    }
    
    override func getAllSections() -> [ProfileDataSource.SectionType] {
        return ProfileDataSource.SectionType.allCases
    }

    override func retrieveDataForSnapshot() async -> [ProfileDataSource.SectionType : [ProfileDataSource.ItemType]] {
        return [:]
    }
    
    /// The currently running task that is loading conversations.
    private var loadMomentsTask: Task<Void, Never>?
    
    private func startLoadAllMoments() {
        self.loadMomentsTask?.cancel()

        self.loadMomentsTask = Task { [weak self] in
            guard let self else { return }
            
            self.collectionView.collectionViewLayout = MomentsCollectionViewLayout()
            
            let moments = try? await MomentsStore.shared.getLast14DaysMoments(for: self.person)
            
            var items: [ProfileDataSource.ItemType] = []
            
            let weekday = Date.today.weekday
            let daysTillSat = 7 - weekday
            
            // Add the rest of the week
            if daysTillSat > 0 {
                for i in stride(from: daysTillSat, to: 0, by: -1) {
                    if let date = Date().add(component: .day, amount: i) {
                        var isAvailable: Bool = false
                        if let daysAgo = Date.today.subtract(component: .day, amount: 13),
                           date.isBetween(Date.today, and: daysAgo) {
                            isAvailable = true
                        } else if date.isSameDay(as: Date.today) {
                            isAvailable = true
                        }
                        let model = MomentViewModel(day: date.day,
                                                    month: date.month,
                                                    year: date.year,
                                                    isAvailable: isAvailable)
                        items.append(.moment(model))
                    }
                }
            }
            
            // Add past dates
            let allDays: Int = daysTillSat == 0 ? 14 : 21
            for i in stride(from: 0, to: allDays - daysTillSat, by: 1) {
                if let date = Date().subtract(component: .day, amount: i) {
                    var isAvailable: Bool = false
                    if let daysAgo = Date.today.subtract(component: .day, amount: 13),
                       date.isBetween(Date.today, and: daysAgo) {
                        isAvailable = true
                    } else if date.isSameDay(as: Date.today) {
                        isAvailable = true
                    }
                    
                    if let moment = moments?.first(where: { moment in
                        if let createdAt = moment.createdAt, createdAt.isSameDay(as: date) {
                            return true
                        } else {
                            return false
                        }
                    }) {
                        let model = MomentViewModel(day: date.day,
                                                    month: date.month,
                                                    year: date.year,
                                                    momentId: moment.objectId!,
                                                    isAvailable: isAvailable)
                        items.append(.moment(model))
                    } else {
                        let model = MomentViewModel(day: date.day,
                                                    month: date.month,
                                                    year: date.year,
                                                    isAvailable: isAvailable)
                        items.append(.moment(model))
                    }
                }
            }
            
            var snapshot = self.dataSource.snapshot()
            snapshot.setItems([], in: .conversations)
            snapshot.setItems(items.reversed(), in: .moments)
            await self.dataSource.apply(snapshot)
                        
        }.add(to: self.autocancelTaskPool)
    }

    // MARK: - Conversation Loading

    /// The currently running task that is loading conversations.
    private var loadConversationsTask: Task<Void, Never>?
    
    private func startLoadAllTask() {
        self.loadConversationsTask?.cancel()

        self.loadConversationsTask = Task { @MainActor [weak self] in
            guard let self,
                  let requiredMemberIDs = self.requiredConversationMemberIDs else { return }

            self.collectionView.collectionViewLayout = ProfileCollectionViewLayout()

            let controller = self.makeConversationListController()
            do {
                try await controller.synchronize(pageSize: Self.conversationPageSize)
                try await self.loadEnoughVisibleConversations(
                    with: controller,
                    requiredMemberIDs: requiredMemberIDs
                )
            } catch {
                logError(error)
            }

            guard !Task.isCancelled,
                  self.segmentControl.selectedSegmentIndex
                    == ProfileSegmentControl.SegmentType.conversations.rawValue else { return }
            await self.applyConversationSnapshot(requiredMemberIDs: requiredMemberIDs)
        }.add(to: self.autocancelTaskPool)
    }

    @MainActor
    private func applyConversationSnapshot(requiredMemberIDs: Set<String>) async {
        let items = self.items(
            from: self.conversationListController?.conversations ?? [],
            requiredMemberIDs: requiredMemberIDs
        )
        var snapshot = self.dataSource.snapshot()
        snapshot.setItems([], in: .moments)
        snapshot.setItems(items, in: .conversations)

        await self.dataSource.apply(snapshot)
    }

    private var requiredConversationMemberIDs: Set<String>? {
        guard let user = self.person as? User,
              let userID = user.objectId,
              let currentUserID = User.current()?.objectId else { return nil }
        return user.isCurrentUser ? [userID] : [currentUserID, userID]
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
                          self.segmentControl.selectedSegmentIndex
                            == ProfileSegmentControl.SegmentType.conversations.rawValue,
                          let requiredMemberIDs = self.requiredConversationMemberIDs else { return }
                    await self.applyConversationSnapshot(requiredMemberIDs: requiredMemberIDs)
                }
            }
        return controller
    }

    private func items(
        from conversations: [ParseConversation],
        requiredMemberIDs: Set<String>
    ) -> [ProfileDataSource.ItemType] {
        conversations
            .filter { conversation in
                let activeMemberIDs = Set(conversation.activeMembers.map(\.userID))
                return conversation.kind != .moment
                    && activeMemberIDs.isSuperset(of: requiredMemberIDs)
                    && conversation.latestMessages.contains { !$0.isDeleted }
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id > rhs.id }
                return lhs.createdAt > rhs.createdAt
            }
            .map { .conversation($0.id) }
    }

    private func loadEnoughVisibleConversations(
        with controller: ParseConversationListController,
        requiredMemberIDs: Set<String>
    ) async throws {
        while self.items(
            from: controller.conversations,
            requiredMemberIDs: requiredMemberIDs
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

        guard self.segmentControl.selectedSegmentIndex
                == ProfileSegmentControl.SegmentType.conversations.rawValue,
              indexPath.item >= collectionView.numberOfItems(inSection: indexPath.section) - 2,
              self.loadNextConversationsTask == nil,
              let controller = self.conversationListController,
              !controller.hasLoadedAllConversations,
              let requiredMemberIDs = self.requiredConversationMemberIDs else { return }

        self.loadNextConversationsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.loadNextConversationsTask = nil }

            let previousCount = self.items(
                from: controller.conversations,
                requiredMemberIDs: requiredMemberIDs
            ).count
            do {
                repeat {
                    try await controller.loadNextConversations(limit: Self.conversationPageSize)
                } while self.items(
                    from: controller.conversations,
                    requiredMemberIDs: requiredMemberIDs
                ).count == previousCount && !controller.hasLoadedAllConversations
            } catch {
                logError(error)
            }

            guard !Task.isCancelled,
                  self.segmentControl.selectedSegmentIndex
                    == ProfileSegmentControl.SegmentType.conversations.rawValue else { return }
            await self.applyConversationSnapshot(requiredMemberIDs: requiredMemberIDs)
        }.add(to: self.autocancelTaskPool)
    }
}
