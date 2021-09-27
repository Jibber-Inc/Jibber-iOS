//
//  CollectionViewDataSource.swift
//  CollectionViewDataSource
//
//  Created by Martin Young on 8/25/21.
//  Copyright © 2021 Benjamin Dodgson. All rights reserved.
//

import Foundation

/// A base class for types that can act as a data source for a UICollectionview.
/// Subclasses should override functions related to dequeuing cells and supplementary views.
/// This class works the same as UICollectionViewDiffableDataSource but it allows you to subclass it more easily and hold additional state.
@MainActor
class CollectionViewDataSource<SectionType: Hashable, ItemType: Hashable> {

    typealias DiffableDataSourceType = UICollectionViewDiffableDataSource<SectionType, ItemType>
    typealias SnapshotType = NSDiffableDataSourceSnapshot<SectionType, ItemType>

    private var diffableDataSource: DiffableDataSourceType!

    required init(collectionView: UICollectionView) {
        self.diffableDataSource = DiffableDataSourceType(collectionView: collectionView,
                                                         cellProvider: { collectionView, indexPath, itemIdentifier in
            guard let section = self.sectionIdentifier(for: indexPath.section) else { return nil }

            return self.dequeueCell(with: collectionView,
                                    indexPath: indexPath,
                                    section: section,
                                    item: itemIdentifier)
        })

        self.diffableDataSource.supplementaryViewProvider =
        { (collectionView: UICollectionView, kind: String, indexPath: IndexPath) -> UICollectionReusableView? in
            guard let section = self.sectionIdentifier(for: indexPath.section) else { return nil }

            return self.dequeueSupplementaryView(with: collectionView,
                                                 kind: kind,
                                                 section: section,
                                                 indexPath: indexPath)
        }

    }
    /// Returns a configured UICollectionViewCell dequeued from the passed in collection view.
    func dequeueCell(with collectionView: UICollectionView,
                     indexPath: IndexPath,
                     section: SectionType,
                     item: ItemType) -> UICollectionViewCell? {
        fatalError()
    }

    /// Returns a configured supplemental view dequeued from the passed in collection view.
    func dequeueSupplementaryView(with collectionView: UICollectionView,
                                  kind: String,
                                  section: SectionType,
                                  indexPath: IndexPath) -> UICollectionReusableView? {
        return nil
    }
}


// MARK: - NSDiffableDataSource Functions

// These functions just forward to the corresponding functions to the underlying NSDiffableDataSource
extension CollectionViewDataSource {

    // MARK: - Standard DataSource Functions

    func apply(_ snapshot: SnapshotType, animatingDifferences: Bool = true) {
        self.diffableDataSource.apply(snapshot, animatingDifferences: animatingDifferences, completion: nil)
    }

    func apply(_ snapshot: SnapshotType,
               animatingDifferences: Bool = true) async {

        await self.diffableDataSource.apply(snapshot, animatingDifferences: animatingDifferences)
    }

    func applySnapshotUsingReloadData(_ snapshot: SnapshotType) async {
        await self.diffableDataSource.applySnapshotUsingReloadData(snapshot)
    }

    func snapshot() -> SnapshotType {
        return self.diffableDataSource.snapshot()
    }

    func sectionIdentifier(for index: Int) -> SectionType? {
        return self.diffableDataSource.sectionIdentifier(for: index)
    }

    func index(for sectionIdentifier: SectionType) -> Int? {
        return self.diffableDataSource.index(for: sectionIdentifier)
    }

    func itemIdentifier(for indexPath: IndexPath) -> ItemType? {
        return self.diffableDataSource.itemIdentifier(for: indexPath)
    }

    func indexPath(for itemIdentifier: ItemType) -> IndexPath? {
        return self.diffableDataSource.indexPath(for: itemIdentifier)
    }
}

// MARK: - Snapshot Convenience Functions

extension CollectionViewDataSource {

    // Synchronous Functions

    func applyChanges(_ changes: (inout SnapshotType) -> Void) {
        var snapshot = self.snapshot()
        changes(&snapshot)
        self.apply(snapshot)
    }

    func appendItems(_ identifiers: [ItemType], toSection sectionIdentifier: SectionType? = nil) {
        self.applyChanges { snapshot in
            snapshot.appendItems(identifiers, toSection: sectionIdentifier)
        }
    }

    func insertItems(_ identifiers: [ItemType], beforeItem beforeIdentifier: ItemType) {
        self.applyChanges { snapshot in
            snapshot.insertItems(identifiers, beforeItem: beforeIdentifier)
        }
    }

    func insertItems(_ identifiers: [ItemType], afterItem afterIdentifier: ItemType) {
        self.applyChanges { snapshot in
            snapshot.insertItems(identifiers, afterItem: afterIdentifier)
        }
    }

    func deleteItems(_ identifiers: [ItemType]) {
        self.applyChanges { snapshot in
            snapshot.deleteItems(identifiers)
        }
    }

    func deleteAllItems() {
        self.applyChanges { snapshot in
            snapshot.deleteAllItems()
        }
    }

    func moveItem(_ identifier: ItemType, beforeItem toIdentifier: ItemType) {
        self.applyChanges { snapshot in
            snapshot.moveItem(identifier, beforeItem: toIdentifier)
        }
    }

    func moveItem(_ identifier: ItemType, afterItem toIdentifier: ItemType) {
        self.applyChanges { snapshot in
            snapshot.moveItem(identifier, afterItem: toIdentifier)
        }
    }

    func reloadItems(_ identifiers: [ItemType]) {
        self.applyChanges { snapshot in
            snapshot.reloadItems(identifiers)
        }
    }

    func reconfigureItems(_ identifiers: [ItemType]) {
        self.applyChanges { snapshot in
            snapshot.reconfigureItems(identifiers)
        }
    }

    func appendSections(_ identifiers: [SectionType]) {
        self.applyChanges { snapshot in
            snapshot.appendSections(identifiers)
        }
    }

    func insertSections(_ identifiers: [SectionType], beforeSection toIdentifier: SectionType) {
        self.applyChanges { snapshot in
            snapshot.insertSections(identifiers, beforeSection: toIdentifier)
        }
    }

    func insertSections(_ identifiers: [SectionType], afterSection toIdentifier: SectionType) {
        self.applyChanges { snapshot in
            snapshot.insertSections(identifiers, afterSection: toIdentifier)
        }
    }

    func deleteSections(_ identifiers: [SectionType]) {
        self.applyChanges { snapshot in
            snapshot.deleteSections(identifiers)
        }
    }

    func moveSection(_ identifier: SectionType, beforeSection toIdentifier: SectionType) {
        self.applyChanges { snapshot in
            snapshot.moveSection(identifier, beforeSection: toIdentifier)
        }
    }

    func moveSection(_ identifier: SectionType, afterSection toIdentifier: SectionType) {
        self.applyChanges { snapshot in
            snapshot.moveSection(identifier, afterSection: toIdentifier)
        }
    }

    func reloadSections(_ identifiers: [SectionType]) {
        self.applyChanges { snapshot in
            snapshot.reloadSections(identifiers)
        }
    }

    // Asynchronous Functions

    func applyChanges(_ changes: (inout SnapshotType) -> Void) async {
        var snapshot = self.snapshot()
        changes(&snapshot)
        await self.apply(snapshot)
    }

    func appendItems(_ identifiers: [ItemType], toSection sectionIdentifier: SectionType? = nil) async {
        await self.applyChanges { snapshot in
            snapshot.appendItems(identifiers, toSection: sectionIdentifier)
        }
    }

    func insertItems(_ identifiers: [ItemType], beforeItem beforeIdentifier: ItemType) async {
        await self.applyChanges { snapshot in
            snapshot.insertItems(identifiers, beforeItem: beforeIdentifier)
        }
    }

    func insertItems(_ identifiers: [ItemType], afterItem afterIdentifier: ItemType) async {
        await self.applyChanges { snapshot in
            snapshot.insertItems(identifiers, afterItem: afterIdentifier)
        }
    }

    func deleteItems(_ identifiers: [ItemType]) async {
        await self.applyChanges { snapshot in
            snapshot.deleteItems(identifiers)
        }
    }

    func deleteAllItems() async {
        await self.applyChanges { snapshot in
            snapshot.deleteAllItems()
        }
    }

    func moveItem(_ identifier: ItemType, beforeItem toIdentifier: ItemType) async {
        await self.applyChanges { snapshot in
            snapshot.moveItem(identifier, beforeItem: toIdentifier)
        }
    }

    func moveItem(_ identifier: ItemType, afterItem toIdentifier: ItemType) async {
        await self.applyChanges { snapshot in
            snapshot.moveItem(identifier, afterItem: toIdentifier)
        }
    }

    func reloadItems(_ identifiers: [ItemType]) async {
        await self.applyChanges { snapshot in
            snapshot.reloadItems(identifiers)
        }
    }

    func reconfigureItems(_ identifiers: [ItemType]) async {
        await self.applyChanges { snapshot in
            snapshot.reconfigureItems(identifiers)
        }
    }

    func appendSections(_ identifiers: [SectionType]) async {
        await self.applyChanges { snapshot in
            snapshot.appendSections(identifiers)
        }
    }

    func insertSections(_ identifiers: [SectionType], beforeSection toIdentifier: SectionType) async {
        await self.applyChanges { snapshot in
            snapshot.insertSections(identifiers, beforeSection: toIdentifier)
        }
    }

    func insertSections(_ identifiers: [SectionType], afterSection toIdentifier: SectionType) async {
        await self.applyChanges { snapshot in
            snapshot.insertSections(identifiers, afterSection: toIdentifier)
        }
    }

    func deleteSections(_ identifiers: [SectionType]) async {
        await self.applyChanges { snapshot in
            snapshot.deleteSections(identifiers)
        }
    }

    func moveSection(_ identifier: SectionType, beforeSection toIdentifier: SectionType) async {
        await self.applyChanges { snapshot in
            snapshot.moveSection(identifier, beforeSection: toIdentifier)
        }
    }

    func moveSection(_ identifier: SectionType, afterSection toIdentifier: SectionType) async {
        await self.applyChanges { snapshot in
            snapshot.moveSection(identifier, afterSection: toIdentifier)
        }
    }

    func reloadSections(_ identifiers: [SectionType]) async {
        await self.applyChanges { snapshot in
            snapshot.reloadSections(identifiers)
        }
    }
}

// MARK: - Custom Animations for Snapshots

// Functions to do custom animations to the collection view in conjunctions with applying snapshots.
extension CollectionViewDataSource {

    /// Applies the snapshot while adjusting the related collectionview's content offset so that the visible cells don't move.
    /// For example, say there are 4 cells and cells 1 and 2 are visible:  0 [1  2] 3 (brackets symbolize viewport)
    /// If 2 more items are are added to the beginning of the collectionview, the viewport will stay centered on the items like so:
    /// -2 -1 0 [1 2] 3
    @MainActor
    func applySnapshotKeepingVisualOffset(_ snapshot: SnapshotType, collectionView: UICollectionView) async {
        // Note the content size before any updates are applied
        let beforeContentSize = collectionView.contentSize

        // Reload
        await self.apply(snapshot, animatingDifferences: false)

        collectionView.layoutIfNeeded()
        let afterContentSize = collectionView.contentSize

        // reset the contentOffset after data is updated
        let newOffset = CGPoint(
            x: collectionView.contentOffset.x + (afterContentSize.width - beforeContentSize.width),
            y: collectionView.contentOffset.y + (afterContentSize.height - beforeContentSize.height))
        collectionView.setContentOffset(newOffset, animated: false)
    }

    /// Animates the first part of the animation cycle, applies the snapshot, then finishes the animation cycle.
    @MainActor
    func apply(_ snapshot: SnapshotType,
               collectionView: UICollectionView,
               animationCycle: AnimationCycle) async {

        await collectionView.animateOut(position: animationCycle.outToPosition,
                                        concatenate: animationCycle.shouldConcatenate)

        // HACK: If we want to scroll to the end of the content, push the content way past the edge
        // so we don't preload any cells undesired cells when the snapshop is applied.
        if animationCycle.scrollToEnd {
            collectionView.contentOffset = CGPoint(x: 999_999_999_999,
                                                   y: 0)
        }

        await self.applySnapshotUsingReloadData(snapshot)

        // If specified, scroll to the last item in the collection view.
        if animationCycle.scrollToEnd {
            let sectionIndex = collectionView.numberOfSections - 1
            let itemIndex = collectionView.numberOfItems(inSection: sectionIndex) - 1
            let indexPath = IndexPath(item: itemIndex, section: sectionIndex)

            // Make sure the index path is valid
            if sectionIndex >= 0 && itemIndex >= 0 {
                collectionView.scrollToItem(at: indexPath,
                                            at: [.centeredHorizontally], animated: false)
            } else {
                collectionView.setContentOffset(.zero, animated: false)
            }
        }
        
        await collectionView.animateIn(position: animationCycle.inFromPosition,
                                       concatenate: animationCycle.shouldConcatenate)
    }
}
