import XCTest
@testable import MessagingContracts

final class MessagingTimelineWindowTests: XCTestCase {
    func testVisibleWindowDoesNotGrowWithConversationHistory() {
        for itemCount in [25, 250, 1_000] {
            let range = MessagingTimelineWindow.visibleItemIndices(
                itemCount: itemCount,
                currentPosition: 10,
                stackDepth: 3
            )

            XCTAssertEqual(range, 7..<12, "Unexpected range for \(itemCount) messages")
            XCTAssertEqual(range.count, 5)
        }
    }

    func testVisibleWindowAtOldestBoundary() {
        XCTAssertEqual(
            MessagingTimelineWindow.visibleItemIndices(
                itemCount: 25,
                currentPosition: 0,
                stackDepth: 3
            ),
            0..<2
        )
    }

    func testVisibleWindowAtNewestBoundary() {
        XCTAssertEqual(
            MessagingTimelineWindow.visibleItemIndices(
                itemCount: 25,
                currentPosition: 24,
                stackDepth: 3
            ),
            21..<25
        )
    }

    func testVisibleWindowTracksFractionalPosition() {
        XCTAssertEqual(
            MessagingTimelineWindow.visibleItemIndices(
                itemCount: 25,
                currentPosition: 10.5,
                stackDepth: 3
            ),
            8..<12
        )
    }

    func testVisibleWindowHandlesBounceOutsideTimeline() {
        XCTAssertEqual(
            MessagingTimelineWindow.visibleItemIndices(
                itemCount: 25,
                currentPosition: -0.5,
                stackDepth: 3
            ),
            0..<1
        )
        XCTAssertEqual(
            MessagingTimelineWindow.visibleItemIndices(
                itemCount: 25,
                currentPosition: 24.5,
                stackDepth: 3
            ),
            22..<25
        )
        XCTAssertTrue(
            MessagingTimelineWindow.visibleItemIndices(
                itemCount: 25,
                currentPosition: 28,
                stackDepth: 3
            ).isEmpty
        )
    }

    func testVisibleWindowRejectsInvalidInputs() {
        XCTAssertTrue(
            MessagingTimelineWindow.visibleItemIndices(
                itemCount: 0,
                currentPosition: 0,
                stackDepth: 3
            ).isEmpty
        )
        XCTAssertTrue(
            MessagingTimelineWindow.visibleItemIndices(
                itemCount: 25,
                currentPosition: .infinity,
                stackDepth: 3
            ).isEmpty
        )
        XCTAssertTrue(
            MessagingTimelineWindow.visibleItemIndices(
                itemCount: 25,
                currentPosition: 0,
                stackDepth: 0
            ).isEmpty
        )
    }
}
