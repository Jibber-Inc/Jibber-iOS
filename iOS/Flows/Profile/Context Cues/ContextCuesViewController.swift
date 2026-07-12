//
//  ContextCuesViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/22/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation


class ContextCuesViewController: DiffableCollectionViewController<ContextCueCollectionViewDataSource.SectionType,
                                 ContextCueCollectionViewDataSource.ItemType,
                                 ContextCueCollectionViewDataSource> {
    
    let lineView = BaseView()
    let person: PersonType
    let addButton = AddView()
        
    init(person: PersonType) {
        self.person = person
        super.init(with: ContextCueCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.insertSubview(self.lineView, belowSubview: self.collectionView)
        self.lineView.set(backgroundColor: .B2)
        self.lineView.alpha = 0.5
        
        if let user = self.person as? User, user.isCurrentUser {
            self.view.insertSubview(self.addButton, aboveSubview: self.collectionView)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.collectionView.allowsMultipleSelection = false 
        self.loadInitialData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.lineView.expandToSuperviewWidth()
        self.lineView.height = 1
        self.lineView.centerOnXAndY()
        
        self.addButton.squaredSize = self.view.height
        self.addButton.pin(.right, offset: .xtraLong)
        self.addButton.centerOnY()
    }
    
    override func getAllSections() -> [ContextCueCollectionViewDataSource.SectionType] {
        return ContextCueCollectionViewDataSource.SectionType.allCases
    }

    override func retrieveDataForSnapshot() async -> [ContextCueCollectionViewDataSource.SectionType : [ContextCueCollectionViewDataSource.ItemType]] {
        var data: [ContextCueCollectionViewDataSource.SectionType : [ContextCueCollectionViewDataSource.ItemType]] = [:]
        
        guard let user = self.person as? User,
              let contextCues = try? await ContextCue.fetchAll(for: user) else { return data }
        
        data[.contextCues] = contextCues.reversed().compactMap({ contextCue in
            return .contextCue(contextCue)
        })
        
        return data
    }
    
    private var loadTask: Task<Void, Never>?
    func reloadContextCues() {
        self.loadTask?.cancel()
        
        self.loadTask = Task { @MainActor [weak self] in
            guard let `self` = self else { return }
            guard let user = self.person as? User,
                  let contextCues = try? await ContextCue.fetchAll(for: user) else { return }
            
            let items: [ContextCueCollectionViewDataSource.ItemType] = contextCues.reversed().compactMap({ contextCue in
                return .contextCue(contextCue)
            })
        
            self.dataSource.setItemsImmediately(items, in: .contextCues)
        }
    }
}
