import XCTest
@testable import MessagingContracts

final class MessagingNotificationRouteTests: XCTestCase {
    func testReplyPushLoadsRootAndPreservesSpecificReplyWithoutCacheLookup() {
        let route = MessagingNotificationRoute(
            messageID: "reply-42",
            threadRootMessageID: "root-7"
        )

        XCTAssertEqual(route.navigationMessageID, "root-7")
        XCTAssertEqual(route.startingReplyMessageID, "reply-42")
        XCTAssertTrue(route.isThreadReply)
    }

    func testRootPushRemainsConversationNavigation() {
        let route = MessagingNotificationRoute(
            messageID: "root-7",
            threadRootMessageID: "root-7"
        )

        XCTAssertEqual(route.navigationMessageID, "root-7")
        XCTAssertNil(route.startingReplyMessageID)
        XCTAssertFalse(route.isThreadReply)
    }

    func testLegacyPushWithoutThreadRootKeepsMessageNavigation() {
        let route = MessagingNotificationRoute(
            messageID: "message-9",
            threadRootMessageID: nil
        )

        XCTAssertEqual(route.navigationMessageID, "message-9")
        XCTAssertNil(route.startingReplyMessageID)
        XCTAssertFalse(route.isThreadReply)
    }
}
