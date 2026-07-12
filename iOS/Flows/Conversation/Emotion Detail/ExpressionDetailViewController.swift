//
//  EmotionDetailViewController.swift
//  Jibber
//
//  Created by Martin Young on 4/25/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Transitions
import Combine

protocol ExpressionDetailViewControllerDelegate: AnyObject {
    func emotionDetailViewControllerDidFinish(_ controller: ExpressionDetailViewController)
}

class ExpressionDetailViewController: DiffableCollectionViewController<EmotionDetailSection,
                                      EmotionDetailItem,
                                      EmotionDetailCollectionViewDataSource> {

    unowned let delegate: ExpressionDetailViewControllerDelegate

    private var emotions: [Emotion] = []
    private let startingExpression: ExpressionInfo?
    var expressions: [ExpressionInfo]
    let message: Messageable?
    
    let pageIndicator = PagingIndicatorView(with: .onExpressionIndexChanged)
    let button = ThemeButton()
    
    private var controller: MessageController?
    private var subscriptions = Set<AnyCancellable>()

    init(startingExpression: ExpressionInfo?,
         expressions: [ExpressionInfo],
         message: Messageable?,
         delegate: ExpressionDetailViewControllerDelegate) {

        self.startingExpression = startingExpression
        self.expressions = expressions
        self.message = message
        self.delegate = delegate

        let collectionView = CollectionView(layout: EmotionDetailCollectionViewLayout())

        super.init(with: collectionView)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()

        self.view.didSelect { [weak self] in
            guard let self else { return }
            self.delegate.emotionDetailViewControllerDidFinish(self)
        }
        
        self.view.insertSubview(self.pageIndicator, aboveSubview: self.collectionView)
        
        self.view.addSubview(self.button)
        self.button.set(style: .custom(color: .white, textColor: .B0, text: "Add"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.modalPresentationStyle = .overFullScreen

        self.loadInitialData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.button.setSize(with: self.view.width)
        self.button.centerOnX()
        self.button.pinToSafeAreaBottom()
        
        self.pageIndicator.height = 20
        self.pageIndicator.expandToSuperviewWidth()
        self.pageIndicator.match(.bottom, to: .top, of: self.button, offset: .negative(.long))
    }
    
    override func collectionViewDataWasLoaded() {
        super.collectionViewDataWasLoaded()
        
        if let message = self.message {
            self.controller = MessageController.controller(for: message)
            self.subscribeToUpdates()
        }
    }
    
    override func getAllSections() -> [EmotionDetailCollectionViewDataSource.SectionType] {
        return EmotionDetailCollectionViewDataSource.SectionType.allCases
    }

    override func retrieveDataForSnapshot() async
    -> [EmotionDetailCollectionViewDataSource.SectionType : [EmotionDetailCollectionViewDataSource.ItemType]] {

        var data: [EmotionDetailSection : [EmotionDetailItem]] = [:]
        let items: [EmotionDetailItem] = self.expressions.compactMap({ info in
            return .expression(info)
        })
        
        data[.info] = items
        
        self.pageIndicator.pageIndicator.numberOfPages = items.count
        self.pageIndicator.layoutNow()

        return data
    }
    
    private func subscribeToUpdates() {
        
        self.controller?.messageChangePublisher.mainSink(receiveValue: { [unowned self] _ in
            
            Task {
                let expressions = self.controller?.message?.expressions ?? []
                
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

extension ExpressionDetailViewController: TransitionableViewController {

    var dismissalType: TransitionType {
        return .custom(type: "blur", model: nil, duration: Theme.animationDurationSlow)
    }

    var presentationType: TransitionType {
        return .custom(type: "blur", model: nil, duration: Theme.animationDurationSlow)
    }
}
