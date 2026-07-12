//
//  EmojiPickerViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 3/25/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation
import Combine
import Localization

class EmojiPickerViewController: DiffableCollectionViewController<EmojiCollectionViewDataSource.SectionType,
                                       EmojiCollectionViewDataSource.ItemType,
                                       EmojiCollectionViewDataSource> {
            
    @Published var selectedEmojis: [Emoji] = []
    
    private let bottomGradientView = GradientPassThroughView(with: [ThemeColor.B0.color.cgColor, ThemeColor.B0.color.withAlphaComponent(0.0).cgColor],
                                                  startPoint: .bottomCenter,
                                                  endPoint: .topCenter)

    init() {
        super.init(with: EmojiCollectionView())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func initializeViews() {
        super.initializeViews()
        
        self.view.set(backgroundColor: .B0)
                        
        self.view.addSubview(self.bottomGradientView)
        
        self.collectionView.allowsMultipleSelection = true
        
        self.setupNavigationBar()
    }
    
    func setupNavigationBar() {
        self.navigationItem.title = "Update Vibe"
        
        let cancel = UIAction { _ in
            self.dismiss(animated: true, completion: nil)
        }
        let rightItem = UIBarButtonItem(title: "Cancel", image: nil, primaryAction: cancel, menu: nil)
        rightItem.tintColor = ThemeColor.D1.color
        let search = UISearchController(searchResultsController: nil)
        search.searchBar.delegate = self
        search.searchBar.scopeButtonTitles = EmojiCategory.allCases.map({ category in
            return category.scopeTitle
        })
        search.searchBar.placeholder = "Search Emojis"
        search.searchBar.selectedScopeButtonIndex = 0
        search.searchBar.showsScopeBar = true
        search.searchBar.tintColor = ThemeColor.D1.color
        self.navigationItem.searchController = search
            
        self.navigationItem.rightBarButtonItem = rightItem
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.loadEmojis(for: .smileysAndPeople)
        
        self.$selectedEmojis.mainSink { [unowned self] items in
            self.updateSelectedItems()
        }.store(in: &self.cancellables)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.bottomGradientView.expandToSuperviewWidth()
        self.bottomGradientView.height = 94
        self.bottomGradientView.pin(.bottom)
    }
    
    func getAllAvailableEmojis() -> [Emoji] {
        return EmojiCategory.allEmojis
    }
    
    override func getAllSections() -> [EmojiCollectionViewDataSource.SectionType] {
        return EmojiCollectionViewDataSource.SectionType.allCases
    }

    override func retrieveDataForSnapshot() async -> [EmojiCollectionViewDataSource.SectionType : [EmojiCollectionViewDataSource.ItemType]] {
        return [:]
    }
    
    func updateSelectedItems() {
        guard !self.dataSource.sectionIdentifier(for: 0).isNil else { return }
        
        let updatedItems: [EmojiCollectionViewDataSource.ItemType] = self.dataSource.itemIdentifiers(in: .emojis).compactMap { item in
            switch item {
            case .emoji(let emoji):
                var copy = emoji
                copy.isSelected = self.selectedEmojis.contains(where: { current in
                    return current.id == emoji.id
                })

                return .emoji(copy)
            }
        }
        
        var snapshot = self.dataSource.snapshot()
        snapshot.setItems(updatedItems, in: .emojis)
        self.dataSource.apply(snapshot)
    }
    
    /// The currently running task that is loading conversations.
    private var loadEmojisTask: Task<Void, Never>?
    
    func loadEmojis(for category: EmojiCategory) {
        self.loadEmojisTask?.cancel()
        
        self.loadEmojisTask = Task { [weak self] in
            guard let self else { return }
                        
            let items: [EmojiCollectionViewDataSource.ItemType] = category.emojis.compactMap({ emoji in
                var copy = emoji

                if self.selectedEmojis.contains(where: { selected in
                    return selected.id == copy.id
                }) {
                    copy.isSelected = true
                }
                
                return .emoji(copy)
            })
            
            guard !Task.isCancelled else { return }
            
            var snapshot = self.dataSource.snapshot()
            snapshot.setItems([], in: .emojis)
            snapshot.setItems(items, in: .emojis)
            
            await self.dataSource.apply(snapshot)
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, didSelectItemAt: indexPath)
        guard let emoji: Emoji = self.dataSource.itemIdentifier(for: indexPath).map({ item in
            switch item {
            case .emoji(let emoji):
                return emoji
            }
        }) else { return }
        
        if let existing = self.selectedEmojis.first(where: { value in
            return value.id == emoji.id
        }) {
            self.selectedEmojis.remove(object: existing)
        } else {
            self.selectedEmojis.append(emoji)
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, didDeselectItemAt: indexPath)
        guard let emoji: Emoji = self.dataSource.itemIdentifier(for: indexPath).map({ item in
            switch item {
            case .emoji(let emoji):
                return emoji
            }
        }), self.selectedEmojis.contains(where: { value in
            return value.id == emoji.id
        }) else { return }
        
        self.selectedEmojis.remove(object: emoji)
    }
}
