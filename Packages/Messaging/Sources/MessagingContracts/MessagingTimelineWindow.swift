//
//  MessagingTimelineWindow.swift
//  MessagingContracts
//

import Foundation

/// Calculates the small item window needed to render a stacked message timeline.
///
/// `currentPosition` is measured in items, so callers with a point-based scroll
/// offset should pass `contentOffset / itemHeight`. The returned range includes
/// items through both zero-alpha boundary positions to preserve the existing
/// insertion and removal behavior of a time-machine-style stack.
public enum MessagingTimelineWindow {
    public static func visibleItemIndices(
        itemCount: Int,
        currentPosition: Double,
        stackDepth: Int
    ) -> Range<Int> {
        guard itemCount > 0, stackDepth > 0, currentPosition.isFinite else {
            return 0..<0
        }

        // Items behind the focused position remain in the stack for
        // `stackDepth` positions. One item in front is retained while it
        // transitions out of view.
        let firstCandidate = ceil(currentPosition - Double(stackDepth))
        let lastCandidate = floor(currentPosition + 1)
        let lastItemIndex = itemCount - 1

        guard lastCandidate >= 0, firstCandidate <= Double(lastItemIndex) else {
            return 0..<0
        }

        let lowerBound = Int(max(0, firstCandidate))
        let upperBound = Int(min(Double(lastItemIndex), lastCandidate)) + 1
        guard lowerBound < upperBound else { return 0..<0 }

        return lowerBound..<upperBound
    }
}
