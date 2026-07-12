//
//  EmotionViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/27/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Localization

class EmotionsViewController: DiffableCollectionViewController<EmotionsCollectionViewDataSource.SectionType,
                              EmotionsCollectionViewDataSource.ItemType,
                              EmotionsCollectionViewDataSource> {
    
    @Published var selectedEmotions: [Emotion] = []
    
    init() {
        super.init(with: EmotionsCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.collectionView.allowsMultipleSelection = true
                
        self.dataSource.didSelectEmotion = { [unowned self] emotion in
            self.handleSelected(emotion: emotion)
        }
        
        self.dataSource.didSelectRemove = { [unowned self] in
            self.removeLastEmotion()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.loadInitialData()
    }
    
    private func removeLastEmotion() {
        self.selectedEmotions.removeFirst()
        self.updateItems()
    }
    
    private func handleSelected(emotion: Emotion) {
        if self.selectedEmotions.contains(emotion) {
            self.selectedEmotions.remove(object: emotion)
        } else {
            self.selectedEmotions.insert(emotion, at: 0)
        }
        
        self.updateItems()
    }
    
    /// The currently running task that is loading conversations.
    private var loadTask: Task<Void, Never>?
    
    private func updateItems() {
        self.loadTask?.cancel()
        
        self.loadTask = Task { [weak self] in
            guard let self else { return }
            
            var snapshot = self.dataSource.snapshot()
            
            var contentItems: [EmotionsCollectionViewDataSource.ItemType] = self.selectedEmotions.compactMap({ emotion in
                return .emotion(EmotionContentModel(emotion: emotion))
            })
            
            if contentItems.isEmpty {
                contentItems = [.emotion(EmotionContentModel(emotion: nil))]
            }
            
            snapshot.setItems(contentItems, in: .content)
            
            let categoryItems: [EmotionsCollectionViewDataSource.ItemType] = EmotionCategory.allCases.compactMap { category in
                let model = EmotionCategoryModel(category: category, selectedEmotions: self.selectedEmotions)
                return .category(model)
            }
            
            snapshot.setItems(categoryItems, in: .categories)
            
            await self.dataSource.apply(snapshot)
        }
    }
    
    override func getAllSections() -> [EmotionsCollectionViewDataSource.SectionType] {
        return EmotionsCollectionViewDataSource.SectionType.allCases
    }

    override func retrieveDataForSnapshot() async -> [EmotionsCollectionViewDataSource.SectionType : [EmotionsCollectionViewDataSource.ItemType]] {
        var data: [EmotionsCollectionViewDataSource.SectionType : [EmotionsCollectionViewDataSource.ItemType]] = [:]
        
        data[.content] = [.emotion(EmotionContentModel(emotion: nil))]
        
        data[.categories] = EmotionCategory.allCases.compactMap({ category in
            return .category(EmotionCategoryModel(category: category, selectedEmotions: []))
        })
        return data
    }
}
