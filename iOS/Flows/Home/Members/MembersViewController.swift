//
//  ConnectionsViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/9/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import ParseCore

class MembersViewController: DiffableCollectionViewController<MembersDataSource.SectionType,
                             MembersDataSource.ItemType,
                             MembersDataSource>, HomeContentType {
    
    var contentTitle: String {
        return "People"
    }
    
    var membersCollectionView: MembersCollectionView {
        return self.collectionView as! MembersCollectionView
    }
    
    init() {
        super.init(with: MembersCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.membersCollectionView.prepareForReveal()
        self.collectionView.allowsMultipleSelection = false
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        once(caller: self, token: "loadMembers") {
            self.loadInitialData()
        }
    }
    
    override func willEnterForeground() {
        super.willEnterForeground()
        
        self.reloadPeople()
    }
    
    override func getAnimationCycle(with snapshot: NSDiffableDataSourceSnapshot<MembersDataSource.SectionType, MembersDataSource.ItemType>) -> AnimationCycle? {
        return nil
    }
    
    override func collectionViewDataWasLoaded() {
        super.collectionViewDataWasLoaded()
        
        self.membersCollectionView.reveal()
        self.subscribeToUpdates()
    }
    
    override func getAllSections() -> [MembersDataSource.SectionType] {
        return MembersDataSource.SectionType.allCases
    }
    
    override func retrieveDataForSnapshot() async -> [MembersDataSource.SectionType : [MembersDataSource.ItemType]] {
        var data: [MembersDataSource.SectionType: [MembersDataSource.ItemType]] = [:]
        
        try? await PeopleStore.shared.initializeIfNeeded()
        try? await MomentsStore.shared.initializeIfNeeded()
        
        var items: [MembersDataSource.ItemType] = [.memberId(User.current()!.objectId!)]
        
        let connections: [MembersDataSource.ItemType] = PeopleStore.shared.connectedPeople.filter({ type in
            return !type.isCurrentUser
        }).sorted(by: { lhs, rhs in
            guard let lhsUpdated = lhs.updatedAt,
                  let rhsUpdated = rhs.updatedAt else { return false }
            return lhsUpdated > rhsUpdated
        }).compactMap({ type in
            return .memberId(type.personId)
        })
        
        let addItems: [MembersDataSource.ItemType] = PeopleStore.shared.sortedUnclaimedReservationWithoutContact.compactMap { reservation in
            guard let id = reservation.objectId else { return nil }
            return .add(id)
        }
        
        items.append(contentsOf: connections)
        items.append(contentsOf: addItems)
        
        data[.members] = items
        
        return data
    }
    
    private func subscribeToUpdates() {
        PeopleStore.shared.$personDeleted.mainSink { [unowned self] _ in
            self.reloadPeople()
        }.store(in: &self.cancellables)
        
        PeopleStore.shared.$personAdded.mainSink { [unowned self] _ in
            self.reloadPeople()
        }.store(in: &self.cancellables)
    }
    
    private var loadPeopleTask: Task<Void, Never>?
    
    func reloadPeople() {
        
        self.loadPeopleTask?.cancel()
        
        self.loadPeopleTask = Task { [weak self] in
            guard let self else { return }

            var items: [MembersDataSource.ItemType] = [.memberId(User.current()!.objectId!)]
            
            let connections: [MembersDataSource.ItemType] = PeopleStore.shared.connectedPeople.filter({ type in
                return !type.isCurrentUser
            }).sorted(by: { lhs, rhs in
                guard let lhsUpdated = lhs.updatedAt,
                      let rhsUpdated = rhs.updatedAt else { return false }
                return lhsUpdated > rhsUpdated
            }).compactMap({ type in
                return .memberId(type.personId)
            })
            
            let addItems: [MembersDataSource.ItemType] = PeopleStore.shared.sortedUnclaimedReservationWithoutContact.compactMap { reservation in
                guard let id = reservation.objectId else { return nil }
                return .add(id)
            }
            
            items.append(contentsOf: connections)
            items.append(contentsOf: addItems)
            
            var snapshot = self.dataSource.snapshot()
            snapshot.setItems(items, in: .members)
            
            await self.dataSource.apply(snapshot)
        }
    }
}
