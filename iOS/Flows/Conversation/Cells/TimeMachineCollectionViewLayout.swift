//
//  TimelineLayout.swift
//  TimelineExperiment
//
//  Created by Martin Young on 11/16/21.
//

import UIKit

protocol TimeMachineLayoutItem {
    /// Used to determine the order of the time machine items.
    /// A lower value means the item is older and should appear closer to the back.
    var sortValue: Double { get }
}

protocol TimeMachineCollectionViewLayoutDataSource: AnyObject {
    func getTimeMachineItem(forItemAt indexPath: IndexPath) -> TimeMachineLayoutItem?
}

private class TimeMachineCollectionViewLayoutInvalidationContext: UICollectionViewLayoutInvalidationContext {
    /// If true, the z ranges for all the items should be recalculated.
    var shouldRecalculateZRanges = true
}

/// A custom layout for data sorted by time. Up to two cell sections are each displayed as a stack along the z axis.
/// The stacks appear similar to Apple's Time Machine interface, with the newest item in front and older items going out into the distance.
/// As the collection view scrolls up and down, the items move away and toward the user respectively.
class TimeMachineCollectionViewLayout: UICollectionViewLayout {

    typealias SectionIndex = Int

    override class var invalidationContextClass: AnyClass {
        return TimeMachineCollectionViewLayoutInvalidationContext.self
    }

    // MARK: - Data Source
    weak var dataSource: TimeMachineCollectionViewLayoutDataSource?
    var sectionCount: Int {
        return self.collectionView?.numberOfSections ?? 0
    }
    func numberOfItems(inSection section: Int) -> Int {
        guard section < self.sectionCount else { return 0 }
        return self.collectionView?.numberOfItems(inSection: section) ?? 0
    }

    // MARK: - Layout Configuration

    /// The height of the cells.
    var itemHeight: CGFloat = MessageContentView.bubbleHeight + MessageDetailView.height + Theme.ContentOffset.short.value {
        didSet { self.invalidateLayout() }
    }
    /// Keypoints used to gradually shrink down items as they move away.
    var scalingKeyPoints: [CGFloat] = [1, 0.84, 0.65, 0.4]
    /// The amount of vertical space between the tops of adjacent items.
    var spacingKeyPoints: [CGFloat] = [0, 8, 16, 20]
    /// Key points used for the gradually alpha out items further back in the message stack.
    var alphaKeyPoints: [CGFloat] = [1, 1, 1, 0]
    /// The maximum number of messages to show in each section's stack.
    var stackDepth: Int = 3 {
        didSet { self.invalidateLayout() }
    }

    var isShowingDropZone: Bool = false {
        didSet { self.invalidateLayout() }
    }

    // MARK: - Layout State

    /// The current position along the Z axis. This is based off of the collectionview's Y content offset.
    /// The z position ranges from 0 to itemCount*itemHeight
    var zPosition: CGFloat {
        return self.collectionView?.contentOffset.y ?? 0
    }
    /// A cache of item layout attributes so they don't have to be recalculated.
    private var cellLayoutAttributes: [IndexPath : UICollectionViewLayoutAttributes] = [:]
    /// A dictionary of z positions where each item is considered in focus. This means the item is frontmost, most recent, and unscaled.
    private(set) var itemFocusPositions: [IndexPath : CGFloat] = [:]
    /// A dictionary of z ranges for all the items. A z range represents the range that each item will be frontmost in its section
    /// and its scale and position will be unaltered.
    private(set) var itemZRanges: [IndexPath : Range<CGFloat>] = [:]

    // MARK: - UICollectionViewLayout Overrides

    override var collectionViewContentSize: CGSize {
        get {
            guard let collectionView = collectionView else { return .zero }

            let itemCount = CGFloat(self.numberOfItems(inSection: 0) + self.numberOfItems(inSection: 1))
            var height = clamp((itemCount - 1), min: 0) * self.itemHeight

            // Plus 1 ensures that we will still receive the pan gesture, regardless of content size
            height += collectionView.bounds.height + 1
            return CGSize(width: collectionView.bounds.width, height: height)
        }
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        // The positions of the items need to be recalculated for every change to the bounds.
        return true
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect)
    -> UICollectionViewLayoutInvalidationContext {

        let invalidationContext = super.invalidationContext(forBoundsChange: newBounds)

        guard let customInvalidationContext
                = invalidationContext as? TimeMachineCollectionViewLayoutInvalidationContext else {
                    return invalidationContext
                }

        // Changing the bounds doesn't affect item z ranges.
        customInvalidationContext.shouldRecalculateZRanges = false

        return customInvalidationContext
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: context)

        // Clear the layout attributes caches.
        self.cellLayoutAttributes.removeAll()

        guard let customContext = context as? TimeMachineCollectionViewLayoutInvalidationContext else {
            return
        }

        if customContext.shouldRecalculateZRanges {
            self.itemFocusPositions.removeAll()
            self.itemZRanges.removeAll()
        }
    }

    override func prepare() {
        // Don't recalculate z ranges if we already have them cached.
        if self.itemZRanges.isEmpty {
            self.prepareZPositionsAndRanges()
        }

        // Calculate and cache the layout attributes for all the items.
        self.forEachIndexPath { indexPath in
            self.cellLayoutAttributes[indexPath] = self.layoutAttributesForItem(at: indexPath)
        }
    }

    /// Updates the z ranges dictionary for all items.
    private func prepareZPositionsAndRanges() {
        guard let dataSource = self.dataSource else {
            logDebug("Warning: Data source not initialized in \(self)")
            return
        }

        // Get all of the items and sort them by value. This combines all the sections into a flat list.
        var sortedItemIndexPaths: [IndexPath] = []
        self.forEachIndexPath { indexPath in
            sortedItemIndexPaths.append(indexPath)
        }
        sortedItemIndexPaths.sort { indexPath1, indexPath2 in
            let sortValue1 = dataSource.getTimeMachineItem(forItemAt: indexPath1)?.sortValue ?? Double.greatestFiniteMagnitude
            let sortValue2 = dataSource.getTimeMachineItem(forItemAt: indexPath2)?.sortValue ?? Double.greatestFiniteMagnitude
            return sortValue1 < sortValue2
        }

        // Calculate the z range for each item.
        for (sortedItemsIndex, indexPath) in sortedItemIndexPaths.enumerated() {
            self.itemFocusPositions[indexPath] = CGFloat(sortedItemsIndex) * self.itemHeight

            let currentSectionIndex = indexPath.section
            let currentItemIndex = indexPath.item

            // TODO
            var startZ: CGFloat = 0//CGFloat(sortedItemsIndex) * self.itemHeight

            // Each item's z range starts after the end of the previous item's range within its section.
            if let previousRangeInSection = self.itemZRanges[IndexPath(item: currentItemIndex - 1,
                                                                       section: currentSectionIndex)] {

                startZ = previousRangeInSection.upperBound + self.itemHeight
            }

            var endZ = startZ
            for nextSortedItemsIndex in (sortedItemsIndex+1)..<sortedItemIndexPaths.count {
                let nextIndexPath = sortedItemIndexPaths[nextSortedItemsIndex]

                // Each item's z range ends before the beginning of the
                // next item's range from within its section.
                if currentSectionIndex == nextIndexPath.section {
                    endZ = CGFloat(nextSortedItemsIndex) * self.itemHeight - self.itemHeight
                    break
                } else if nextSortedItemsIndex == sortedItemIndexPaths.count - 1 {
                    // If we've hit the last item we must be at the end of the range.
                    endZ = CGFloat(nextSortedItemsIndex) * self.itemHeight
                    break
                }
            }
            
            self.itemZRanges[indexPath] = startZ..<endZ
        }
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // Return all items whose frames intersect with the given rect.
        let itemAttributes = self.cellLayoutAttributes.values.filter { attributes in
            return rect.intersects(attributes.frame)
        }

        return itemAttributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        // If the attributes are cached already, just return those.
        if let attributes = self.cellLayoutAttributes[indexPath]  {
            return attributes
        }

        // All items are positioned relative to the frontmost item in their section.
        guard let frontmostIndexPath = self.getFrontmostIndexPath(in: indexPath.section) else { return nil }

        // OPTIMIZATION: Don't calculate attributes for items that definitely won't be visible.
        guard (-1..<self.stackDepth+1).contains(frontmostIndexPath.item - indexPath.item) else {
            return nil
        }

        let indexOffsetFromFrontmost = CGFloat(frontmostIndexPath.item - indexPath.item)
        let offsetFromFrontmost = indexOffsetFromFrontmost*self.itemHeight

        let frontmostVectorToCurrentZ = self.getFrontmostItemZVector(in: indexPath.section)
        let vectorToCurrentZ = frontmostVectorToCurrentZ+offsetFromFrontmost

        let normalizedZOffset: CGFloat

        if 0 < vectorToCurrentZ {
            // The item's z range is behind the current zPosition.
            normalizedZOffset = -vectorToCurrentZ/(self.itemHeight*CGFloat(self.stackDepth))
        } else if vectorToCurrentZ < 0 {
            // The item's z range is in front of the current zPosition.
            normalizedZOffset = -vectorToCurrentZ/self.itemHeight
        } else {
            // The item's range contains the current zPosition
            normalizedZOffset = 0
        }

        return self.layoutAttributesForItemAt(indexPath: indexPath, withNormalizedZOffset: normalizedZOffset)
    }

    func layoutAttributesForItemAt(indexPath: IndexPath,
                             withNormalizedZOffset normalizedZOffset: CGFloat) -> UICollectionViewLayoutAttributes? {
        guard let collectionView = self.collectionView else { return nil }

        var scale: CGFloat
        var yOffset: CGFloat
        var alpha: CGFloat

        if normalizedZOffset < 0 {
            // Scaling the item down to simulate it moving away from the user.
            scale = lerp(abs(normalizedZOffset), keyPoints: self.scalingKeyPoints)
            yOffset = lerp(abs(normalizedZOffset), keyPoints: self.spacingKeyPoints)
            alpha = lerp(abs(normalizedZOffset), keyPoints: self.alphaKeyPoints)
        } else if normalizedZOffset > 0 {
            // Scale the item up to simulate it moving closer to the user.
            scale = normalizedZOffset + 1
            yOffset = normalizedZOffset * -self.itemHeight * 1
            alpha = 1 - normalizedZOffset
        } else {
            // If current z position is within the item's z range, don't adjust its scale or position.
            scale = 1
            yOffset = 0
            alpha = 1
        }

        let layoutClass = type(of: self).layoutAttributesClass as? UICollectionViewLayoutAttributes.Type
        guard let attributes = layoutClass?.init(forCellWith: indexPath) else { return nil }

        // Make sure items in the front are drawn over items in the back.
        attributes.zIndex = indexPath.item
        attributes.bounds.size = CGSize(width: collectionView.width, height: self.itemHeight)

        let centerPoint = self.getCenterPoint(for: indexPath.section,
                                                 withYOffset: yOffset,
                                                 scale: scale)
        attributes.center = centerPoint
        attributes.transform = CGAffineTransform(scaleX: scale, y: scale)
        attributes.alpha = alpha

        return attributes
    }

    // MARK: - Attribute Helpers

    /// Gets the index path of the frontmost item in the given section.
    func getFrontmostIndexPath(in section: SectionIndex) -> IndexPath? {
        var indexPathCandidate: IndexPath?

        for i in (0..<self.numberOfItems(inSection: section)).reversed() {
            let indexPath = IndexPath(item: i, section: section)

            if indexPathCandidate == nil {
                indexPathCandidate = indexPath
                continue
            }

            guard let range = self.itemZRanges[indexPath] else { continue }
            if range.vector(to: self.zPosition) <= 0 {
                indexPathCandidate = indexPath
            }
        }

        return indexPathCandidate
    }

    /// Gets the z vector from current frontmost item's z range to the current z position.
    private func getFrontmostItemZVector(in section: SectionIndex) -> CGFloat {
        guard let frontmostIndexPath = self.getFrontmostIndexPath(in: section) else { return 0 }

        guard let frontmostRange = self.itemZRanges[frontmostIndexPath] else { return 0 }

        return frontmostRange.vector(to: self.zPosition)
    }

    func getFocusedItemIndexPath() -> IndexPath? {
        let sectionCount = self.sectionCount

        var frontmostIndexes: [IndexPath] = []
        for i in 0..<sectionCount {
            guard let frontmostIndex = self.getFrontmostIndexPath(in: i) else { continue }
            guard let range = self.itemZRanges[frontmostIndex] else { continue }

            if range.vector(to: self.zPosition) > -self.itemHeight {
                frontmostIndexes.append(frontmostIndex)
            }
        }

        return frontmostIndexes.max { indexPath1, indexPath2 in
            guard let lowerBound1 = self.itemZRanges[indexPath1]?.lowerBound else { return true }
            guard let lowerBound2 = self.itemZRanges[indexPath2]?.lowerBound else { return false }
            return lowerBound1 < lowerBound2
        }
    }

    func getMostRecentItemContentOffset() -> CGPoint? {
        guard let mostRecentIndex = self.itemZRanges.max(by: { kvp1, kvp2 in
            return kvp1.value.lowerBound < kvp2.value.lowerBound
        })?.key else { return nil }

        guard let upperBound = self.itemZRanges[mostRecentIndex]?.upperBound else { return nil }
        return CGPoint(x: 0, y: upperBound)
    }

    func getCenterPoint(for section: SectionIndex,
                        withYOffset yOffset: CGFloat,
                        scale: CGFloat) -> CGPoint {

        guard let collectionView = self.collectionView else { return .zero }
        let contentRect = CGRect(x: collectionView.contentOffset.x,
                                 y: collectionView.contentOffset.y,
                                 width: collectionView.bounds.size.width,
                                 height: collectionView.bounds.size.height)
        var centerPoint = CGPoint(x: contentRect.midX, y: contentRect.top + Theme.contentOffset)

        if section == 0 {
            centerPoint.y += self.itemHeight.half
            centerPoint.y += yOffset
            centerPoint.y += self.itemHeight.half * (1-scale)
        } else {
            centerPoint.y += self.itemHeight.doubled - Theme.ContentOffset.short.value
            centerPoint.y -= yOffset
            centerPoint.y -= self.itemHeight.half * (1-scale)
        }

        return centerPoint
    }

    // MARK: - Content Offset Handling

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint,
                                      withScrollingVelocity velocity: CGPoint) -> CGPoint {

        // When finished scrolling, always settle on a cell in a centered position.
        var newOffset = proposedContentOffset
        newOffset.y = round(newOffset.y, toNearest: self.itemHeight)
        newOffset.y = max(newOffset.y, 0)
        return newOffset
    }
}

extension TimeMachineCollectionViewLayout {

    /// Runs the passed in closure on every valid index path in the collection view.
    private func forEachIndexPath(_ apply: (IndexPath) -> Void) {
        let sectionCount = self.sectionCount
        for section in 0..<sectionCount {
            let itemCount = self.numberOfItems(inSection: section)
            for item in 0..<itemCount {
                let indexPath = IndexPath(item: item, section: section)
                apply(indexPath)
            }
        }
    }
}
