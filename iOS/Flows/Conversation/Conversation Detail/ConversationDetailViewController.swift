//
//  MembersViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 11/23/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import JibberParseLiveQuery
import MessagingContracts

class ConversationDetailViewController: DiffableCollectionViewController<ConversationDetailCollectionViewDataSource.SectionType,
                                        ConversationDetailCollectionViewDataSource.ItemType,
                                        ConversationDetailCollectionViewDataSource>,
                                        ActiveConversationable {
    
    private let topGradientView
    = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor, ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                   startPoint: .topCenter,
                   endPoint: .bottomCenter)
    
    private let bottomGradientView
      = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor, ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                     startPoint: .bottomCenter,
                     endPoint: .topCenter)
        
    let conversationController: ParseConversationController
    
    let darkBlurView = DarkBlurView()
    
    init(with conversationId: String) {
        self.conversationController = ParseConversationController.controller(for: conversationId)
        let cv = CollectionView(layout: ConversationDetailCollectionViewLayout())
        cv.showsHorizontalScrollIndicator = false
        cv.contentInset = UIEdgeInsets(top: 30,
                                       left: 0,
                                       bottom: 100,
                                       right: 0)
        super.init(with: cv)
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
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        
        self.view.insertSubview(self.darkBlurView, belowSubview: self.collectionView)
        
        self.view.addSubview(self.topGradientView)
        self.view.addSubview(self.bottomGradientView)
        
        self.collectionView.allowsMultipleSelection = false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.startLoadDataTask()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.darkBlurView.expandToSuperviewSize()
        
        self.topGradientView.expandToSuperviewWidth()
        self.topGradientView.height = Theme.ContentOffset.screenPadding.value
        self.topGradientView.pin(.top)
        
        self.bottomGradientView.expandToSuperviewWidth()
        self.bottomGradientView.height = 94
        self.bottomGradientView.pin(.bottom)
    }
    
    /// A task for loading data and subscribing to conversation updates.
    private var loadDataTask: Task<Void, Never>?
    
    private func startLoadDataTask() {
        self.loadDataTask?.cancel()
        
        self.loadDataTask = Task { [weak self] in
            guard let conversationController = self?.conversationController else {
                // If there's no current conversation, then there's nothing to show.
                await self?.dataSource.deleteAllItems()
                return
            }

            self?.subscribeToUpdates(for: conversationController)

            guard !Task.isCancelled else { return }

            await self?.loadData()
        }
    }
    
    /// The subscriptions for the current conversation.
    private var conversationCancellables = Set<AnyCancellable>()
    
    private func subscribeToUpdates(for conversationController: ParseConversationController) {
        // Clear out previous subscriptions.
        self.conversationCancellables.removeAll()

        conversationController
            .membersChangesPublisher
            .mainSink(receiveValue: { [weak self] changes in
                guard !changes.isEmpty else { return }
                Task { [weak self] in
                    await self?.reloadPeople()
                }
            }).store(in: &self.conversationCancellables)

        conversationController
            .conversationChangePublisher
            .mainSink(receiveValue: { [weak self] _ in
                Task { [weak self] in
                    await self?.loadData()
                }
            }).store(in: &self.conversationCancellables)
        
        Client.shared.shouldPrintWebSocketLog = false
        let reservationQuery = Reservation.allUnclaimedWithContactQuery()
        let reservationSubscription = Client.shared.subscribe(reservationQuery)
        reservationSubscription.handleEvent { [unowned self] query, event in
            
            // If a reservation related to this conversation is updated, then reload the data.
            switch event {
            case .entered(let object), .created(let object),
                    .updated(let object), .left(let object), .deleted(let object):
                
                guard let reservation = object as? Reservation,
                      let cid = reservation.conversationCid else { return }

                guard cid == conversationController.conversationID.rawValue else { return }
                Task {
                    await self.reloadPeople()
                }
            }
        }
    }
    
    func reloadPeople() async {
        guard let conversation = self.conversationController.conversation else { return }
                
        let members = await self.getPeople(for: conversation)
        
        var items: [ConversationDetailCollectionViewDataSource.ItemType] = members.compactMap({ value in
            let item = Member(personId: value.personId,
                              conversationController: nil)
            return .member(item)
        })
        
        if self.isOwnedByCurrentUser(conversation) {
            items.append(.detail(.add))
        }
                
        var snapshot = self.dataSource.snapshot()
        snapshot.setItems(items, in: .people)
        await self.dataSource.apply(snapshot)
    }
    
    override func getAllSections() -> [ConversationDetailCollectionViewDataSource.SectionType] {
        return ConversationDetailCollectionViewDataSource.SectionType.allCases
    }
    
    override func retrieveDataForSnapshot() async -> [ConversationDetailCollectionViewDataSource.SectionType: [ConversationDetailCollectionViewDataSource.ItemType]] {
        
        var data: [ConversationDetailSectionType: [ConversationDetailItemType]] = [:]
        
        guard let conversation = self.conversationController.conversation else { return data }
        
        data[.info] = [.info(conversation.id), .editTopic(conversation.id)]
        
        let members = await self.getPeople(for: conversation)
        
        data[.people] = members.compactMap({ member in
            let member = Member(personId: member.personId,
                                conversationController: nil)
            return .member(member)
        })
        
        var pinnedItems: [ConversationDetailItemType] = conversation.pinnedMessages.compactMap({ message in
            return .pinnedMessage(PinModel(message: message))
        })
        
        if pinnedItems.isEmpty {
            pinnedItems = [.pinnedMessage(PinModel(message: nil))]
        }
        
        data[.pins] = pinnedItems
        
        if self.isOwnedByCurrentUser(conversation) {
            data[.people]?.append(.detail(.add))
            data[.options] = [.detail(.hide), .detail(.leave), .detail(.delete)]
        } else {
            data[.options] = [.detail(.hide), .detail(.leave)]
        }
        
        return data
    }

    private func getPeople(for conversation: ParseConversation) async -> [PersonType] {
        var peopleByID: [String: PersonType] = [:]

        for member in conversation.activeMembers where !member.isCurrentUser {
            guard let person = await PeopleStore.shared.getPerson(withPersonId: member.userID) else {
                continue
            }
            peopleByID[person.personId] = person
        }

        for (_, reservation) in PeopleStore.shared.unclaimedReservations {
            guard reservation.conversationCid == conversation.id,
                  let contactID = reservation.contactId,
                  let person = await PeopleStore.shared.getPerson(withPersonId: contactID) else {
                continue
            }
            peopleByID[person.personId] = person
        }

        return Array(peopleByID.values)
            .sorted { $0.givenName.localizedCaseInsensitiveCompare($1.givenName) == .orderedAscending }
    }

    private func isOwnedByCurrentUser(_ conversation: ParseConversation) -> Bool {
        conversation.currentMember?.role == .owner ||
            conversation.authorId == User.current()?.objectId
    }
}
