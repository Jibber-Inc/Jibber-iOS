//
//  WalletCollectionViewLayout.swift
//  Jibber
//
//  Created by Benji Dodgson on 2/4/22.
//  Copyright © 2022 Benjamin Dodgson. All rights reserved.
//

import Foundation

class WalletCollectionViewLayout: UICollectionViewCompositionalLayout {

    init() {
        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.scrollDirection = .vertical

        super.init(sectionProvider: { sectionIndex, environment in
            
            guard let sectionType = WalletCollectionViewDataSource.SectionType.init(rawValue: sectionIndex) else { return nil }
            
            let sectionInset: CGFloat = Theme.ContentOffset.xtraLong.value
            
            switch sectionType {
            case .achievements:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.33), heightDimension: .fractionalHeight(1.0))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                // Group
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(160))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                // Section
                let section = NSCollectionLayoutSection(group: group)
                return section
            case .transactions:
                                
                // Item
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(70))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                item.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                             leading: sectionInset,
                                                             bottom: 0,
                                                             trailing: sectionInset)

                // Group
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                group.contentInsets = NSDirectionalEdgeInsets(top: 0,
                                                              leading: 0,
                                                              bottom: 0,
                                                              trailing: 0)

                // Section
                let section = NSCollectionLayoutSection(group: group)
                return section
            }
                        
        }, configuration: config)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

}
