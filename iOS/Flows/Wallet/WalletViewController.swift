//
//  WalletViewController.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/4/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class WalletViewController: DiffableCollectionViewController<WalletCollectionViewDataSource.SectionType,
                            WalletCollectionViewDataSource.ItemType,
                            WalletCollectionViewDataSource> {
    init() {
        super.init(with: WalletCollectionView())
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(collectionView: UICollectionView) {
        fatalError("init(collectionView:) has not been implemented")
    }

    override func initializeViews() {
        super.initializeViews()

        self.modalPresentationStyle = .popover
        if let pop = self.popoverPresentationController {
            let sheet = pop.adaptiveSheetPresentationController
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true 
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.set(backgroundColor: .B0)
        
        self.loadInitialData()
    }

    // MARK: Data Loading

    override func getAllSections() -> [WalletCollectionViewDataSource.SectionType] {
        return WalletCollectionViewDataSource.SectionType.allCases
    }

    override func retrieveDataForSnapshot() async -> [WalletCollectionViewDataSource.SectionType: [WalletCollectionViewDataSource.ItemType]] {

        var data: [WalletCollectionViewDataSource.SectionType: [WalletCollectionViewDataSource.ItemType]] = [:]

        guard let transactions = try? await Transaction.fetchAllTransactions() else { return data }

        data[.transactions] = transactions.compactMap({ transaction in
            return .transaction(transaction)
        })

        return data
    }
}
