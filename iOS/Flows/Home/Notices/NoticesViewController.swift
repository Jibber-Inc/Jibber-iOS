//
//  NoticesViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 6/9/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class NoticesViewController: DiffableCollectionViewController<NoticesDataSource.SectionType,
                             NoticesDataSource.ItemType,
                                NoticesDataSource>, HomeContentType {
    
    var contentTitle: String {
        return "Notices"
    }
    
    let noticesFooterView = PagingIndicatorView(with: .onNoticeIndexChanged)
    
    init() {
        super.init(with: NoticesCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.addSubview(self.noticesFooterView)
        
        NoticeStore.shared.$notices
            .mainSink { [unowned self] notices in
                self.reloadNotices()
            }.store(in: &self.cancellables)
        
        self.collectionView.isScrollEnabled = false 
        self.collectionView.allowsMultipleSelection = false 
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.noticesFooterView.height = 20
        self.noticesFooterView.expandToSuperviewWidth()
        self.noticesFooterView.top = self.view.height * 0.6 + Theme.ContentOffset.long.value 
    }
    
    override func getAllSections() -> [NoticesDataSource.SectionType] {
        return NoticesDataSource.SectionType.allCases
    }
    
    override func retrieveDataForSnapshot() async -> [NoticesDataSource.SectionType : [NoticesDataSource.ItemType]] {
        return [:]
    }
    
    private var loadNoticeTask: Task<Void, Never>?
    
    func reloadNotices() {
        
        self.loadNoticeTask?.cancel()
        
        self.loadNoticeTask = Task { @MainActor [weak self] in
            guard let `self` = self else { return }
            
            try? await NoticeStore.shared.initializeIfNeeded()

            let notices = NoticeStore.shared.notices.filter({ notice in
                return notice.type != .unreadMessages
            }).sorted()
            
            let items: [NoticesDataSource.ItemType] = notices.compactMap({ notice in
                return .notice(notice)
            })
            
            self.noticesFooterView.pageIndicator.numberOfPages = items.count
            
            self.dataSource.setItemsImmediately(items, in: .notices)
        }
    }
}
