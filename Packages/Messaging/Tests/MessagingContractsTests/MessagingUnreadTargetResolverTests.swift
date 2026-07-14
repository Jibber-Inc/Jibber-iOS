import XCTest
@testable import MessagingContracts

final class MessagingUnreadTargetResolverTests: XCTestCase {
    func testNoUnreadCountReturnsNone() {
        XCTAssertEqual(
            MessagingUnreadTargetResolver.resolve(
                serverUnreadCount: 0,
                loadedUnreadMessageIDsOldestFirst: ["stale-local-unread"],
                hasLoadedAll: false
            ),
            .none
        )
    }

    func testPartialHistoryNeedsOlderPage() {
        let newestTwentyFiveUnread = (6...30).map { "message-\($0)" }

        XCTAssertEqual(
            MessagingUnreadTargetResolver.resolve(
                serverUnreadCount: 30,
                loadedUnreadMessageIDsOldestFirst: newestTwentyFiveUnread,
                hasLoadedAll: false
            ),
            .needsOlderPage
        )
    }

    func testCompleteUnreadRangeTargetsOldestUnread() {
        let allUnread = (1...30).map { "message-\($0)" }

        XCTAssertEqual(
            MessagingUnreadTargetResolver.resolve(
                serverUnreadCount: 30,
                loadedUnreadMessageIDsOldestFirst: allUnread,
                hasLoadedAll: false
            ),
            .target("message-1")
        )
    }

    func testAuthoritativeCountIgnoresSurplusOlderCandidates() {
        XCTAssertEqual(
            MessagingUnreadTargetResolver.resolve(
                serverUnreadCount: 2,
                loadedUnreadMessageIDsOldestFirst: [
                    "stale-older-candidate",
                    "oldest-authoritative-unread",
                    "newest-unread"
                ],
                hasLoadedAll: true
            ),
            .target("oldest-authoritative-unread")
        )
    }

    func testFullyLoadedHistoryUsesOldestAvailableCandidateWhenCountIsAhead() {
        XCTAssertEqual(
            MessagingUnreadTargetResolver.resolve(
                serverUnreadCount: 3,
                loadedUnreadMessageIDsOldestFirst: ["message-2", "message-3"],
                hasLoadedAll: true
            ),
            .target("message-2")
        )
    }

    func testFullyLoadedHistoryWithoutCandidateReturnsNone() {
        XCTAssertEqual(
            MessagingUnreadTargetResolver.resolve(
                serverUnreadCount: 3,
                loadedUnreadMessageIDsOldestFirst: [],
                hasLoadedAll: true
            ),
            .none
        )
    }

    func testMissingCandidatesNeedOlderPageWhileHistoryRemains() {
        XCTAssertEqual(
            MessagingUnreadTargetResolver.resolve(
                serverUnreadCount: 3,
                loadedUnreadMessageIDsOldestFirst: [],
                hasLoadedAll: false
            ),
            .needsOlderPage
        )
    }

    func testOldestUnreadReplyTargetsItsVisibleRoot() {
        XCTAssertEqual(
            MessagingUnreadTargetResolver.resolveCandidate(
                serverUnreadCount: 2,
                loadedUnreadCandidatesOldestFirst: [
                    MessagingUnreadTargetCandidate(
                        unreadMessageID: "oldest-unread-reply",
                        visibleRootMessageID: "reply-parent"
                    ),
                    MessagingUnreadTargetCandidate(
                        unreadMessageID: "newer-unread-root",
                        visibleRootMessageID: "newer-unread-root"
                    )
                ],
                hasLoadedAll: false
            ),
            .target(MessagingUnreadTargetCandidate(
                unreadMessageID: "oldest-unread-reply",
                visibleRootMessageID: "reply-parent"
            ))
        )
    }

    func testReplyCandidateStillNeedsOlderPageWhenAuthoritativeCountIsAhead() {
        XCTAssertEqual(
            MessagingUnreadTargetResolver.resolveCandidate(
                serverUnreadCount: 2,
                loadedUnreadCandidatesOldestFirst: [
                    MessagingUnreadTargetCandidate(
                        unreadMessageID: "newest-unread-reply",
                        visibleRootMessageID: "reply-parent"
                    )
                ],
                hasLoadedAll: false
            ),
            .needsOlderPage
        )
    }
}
