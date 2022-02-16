//
//  MembersViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/23/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import StreamChat
import Combine

class MembersViewController: DiffableCollectionViewController<MembersCollectionViewDataSource.SectionType,
                             MembersCollectionViewDataSource.ItemType,
                             MembersCollectionViewDataSource>,
                             ActiveConversationable {

    var conversationController: ConversationController?

    init() {
        let cv = CollectionView(layout: MembersCollectionViewLayout())
        cv.isScrollEnabled = false
        cv.showsHorizontalScrollIndicator = false
        super.init(with: cv)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A task for loading data and subscribing to conversation updates.
    private var loadDataTask: Task<Void, Never>?

    override func initializeViews() {
        super.initializeViews()

        self.view.clipsToBounds = false
        self.collectionView.clipsToBounds = false

        self.collectionView.animationView.isHidden = true

        ConversationsManager.shared.$activeConversation
            .removeDuplicates()
            .mainSink { [unowned self] conversation in
                self.loadDataTask?.cancel()

                if let cid = conversation?.cid {
                    self.conversationController = ConversationController.controller(cid)
                } else {
                    self.conversationController = nil
                }

                self.loadDataTask = Task { [weak self] in
                    guard let conversationController = self?.conversationController else {
                        // If there's no current conversation, then there's nothing to show.
                        await self?.dataSource.deleteAllItems()
                        return
                    }

                    await self?.loadData()


                    guard !Task.isCancelled else { return }

                    logDebug("finished loading data for \(conversation?.name)")

                    self?.subscribeToUpdates(for: conversationController)
                }
            }.store(in: &self.cancellables)
    }

    /// The subscriptions for the current conversation.
    private var conversationCancellables = Set<AnyCancellable>()

    private func subscribeToUpdates(for conversationController: ConversationController) {
        // Clear out previous subscriptions.
        self.conversationCancellables.removeAll()

        conversationController
            .typingUsersPublisher
            .mainSink(receiveValue: { [unowned self] typingUsers in
                self.dataSource.reconfigureAllItems()
            }).store(in: &self.conversationCancellables)

        conversationController
            .memberEventPublisher
            .mainSink(receiveValue: { [unowned self] event in
                switch event as MemberEvent {
                case let event as MemberAddedEvent:
                    self.add(member: event.member)
                case let event as MemberRemovedEvent:
                    guard let conversationController = self.conversationController else { return }
                    let member = Member(displayable: AnyHashableDisplayable(event.user),
                                        conversationController: conversationController)
                    self.dataSource.deleteItems([.member(member)])
                case let event as MemberUpdatedEvent:
                    guard let conversationController = self.conversationController else { return }
                    let member = Member(displayable: AnyHashableDisplayable(event.member),
                                        conversationController: conversationController)
                    self.dataSource.reconfigureItems([.member(member)])
                default:
                    break
                }
            }).store(in: &self.conversationCancellables)
    }
    
    func add(member: ChatChannelMember) {
        guard let conversationController = self.conversationController else { return }

        let member = Member(displayable: AnyHashableDisplayable.init(member),
                            conversationController: conversationController)
        self.dataSource.appendItems([.member(member)], toSection: .members)
    }

    /// A task for scrolling to a specific chat user.
    private var scrollToUserTask: Task<Void, Never>?

    func scroll(to user: ChatUser) {
        self.scrollToUserTask?.cancel()

        self.scrollToUserTask = Task { [weak self] in
            // Wait for the data to finish loading before we try to scroll to a specific user.
            await self?.loadDataTask?.value

            guard !Task.isCancelled,
                let controller = self?.conversationController else { return }

            let member = Member(displayable: AnyHashableDisplayable(user),
                                conversationController: controller)
            guard let ip = self?.dataSource.indexPath(for: .member(member)) else { return }

            self?.collectionView.scrollToItem(at: ip, at: .centeredHorizontally, animated: true)
        }
    }

    // MARK: - Data Loading

    override func getAnimationCycle(with snapshot: NSDiffableDataSourceSnapshot<MembersSectionType, MembersItemType>)
    -> AnimationCycle? {

        // Center on the user who sent the most recent message.
        var centeredIndexPath: IndexPath?
        if let conversationController = conversationController,
           let nonCurrentUserMessage = conversationController.messages.first(where: { message in
               return !message.isFromCurrentUser
           }) {
            let user = nonCurrentUserMessage.author
            let member = Member(displayable: AnyHashableDisplayable(user),
                                conversationController: conversationController)
            centeredIndexPath = snapshot.indexPathOfItem(.member(member))
        }

        return AnimationCycle(inFromPosition: nil,
                              outToPosition: nil,
                              shouldConcatenate: false,
                              scrollToIndexPath: centeredIndexPath)
    }

    override func getAllSections() -> [MembersCollectionViewDataSource.SectionType] {
        return MembersCollectionViewDataSource.SectionType.allCases
    }

    override func retrieveDataForSnapshot() async -> [MembersCollectionViewDataSource.SectionType: [MembersCollectionViewDataSource.ItemType]] {

        var data: [MembersCollectionViewDataSource.SectionType: [MembersCollectionViewDataSource.ItemType]] = [:]

        guard let conversation = self.conversationController?.conversation else { return data }

        let members = conversation.lastActiveMembers.filter { member in
            return member.id != ChatClient.shared.currentUserId
        }
        
        data[.members] = members.compactMap({ user in
            guard let conversationController = self.conversationController else { return nil }
            let member = Member(displayable: AnyHashableDisplayable.init(user),
                                conversationController: conversationController)
            return .member(member)
        })

        if !isRelease {
            data[.members]?.append(.add(conversation.cid))
        }

        return data
    }
}
