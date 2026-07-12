//
//  ReactionsDetailViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 8/27/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Transitions
import Combine

class ReactionsDetailViewController: ExpressionDetailViewController {
    
    let blurView = DarkBlurView()
    private let moment: Moment
    
    private(set) var controller: ParseConversationController?
    private var subscriptions = Set<AnyCancellable>()
    
    init(with moment: Moment, delegate: ExpressionDetailViewControllerDelegate) {
        self.moment = moment
        super.init(startingExpression: nil, expressions: [], message: nil, delegate: delegate)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.insertSubview(self.blurView, belowSubview: self.collectionView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.modalPresentationStyle = .popover
        if let pop = self.popoverPresentationController {
            let sheet = pop.adaptiveSheetPresentationController
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.preferredCornerRadius = Theme.screenRadius
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.blurView.expandToSuperviewSize()
    }
    
    override func retrieveDataForSnapshot() async -> [EmotionDetailCollectionViewDataSource.SectionType : [EmotionDetailCollectionViewDataSource.ItemType]] {
        
        self.controller = ParseConversationController(
            conversationID: self.moment.commentsId,
            automaticallySynchronize: false
        )
        try? await self.controller?.synchronize()
        self.expressions = self.controller?.conversation?.expressions ?? []
        
        return await super.retrieveDataForSnapshot()
    }
    
    override func collectionViewDataWasLoaded() {
        super.collectionViewDataWasLoaded()
        
        self.subscribeToUpdates()
    }
    
    private func subscribeToUpdates() {
        self.controller?.conversationChangePublisher.mainSink(receiveValue: { [unowned self] _ in
            
            Task {
                let expressions = self.controller?.conversation?.expressions ?? []
                
                let items: [EmotionDetailCollectionViewDataSource.ItemType] = expressions.compactMap { info in
                    return .expression(info)
                }

                var snapshot = self.dataSource.snapshot()
                snapshot.setItems(items, in: .info)
                
                self.pageIndicator.pageIndicator.numberOfPages = items.count
                self.pageIndicator.layoutNow()
                
                await self.dataSource.apply(snapshot)
            }
            
        }).store(in: &self.subscriptions)
    }
}
