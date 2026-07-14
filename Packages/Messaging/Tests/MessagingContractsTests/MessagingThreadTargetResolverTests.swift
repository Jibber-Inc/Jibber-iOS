//
//  MessagingThreadTargetResolverTests.swift
//  MessagingContractsTests
//

import XCTest
@testable import MessagingContracts

final class MessagingThreadTargetResolverTests: XCTestCase {

    func testRootMessageResolvesToItsServerID() {
        let root = self.message(
            objectID: "root-server",
            clientMessageID: "root-client"
        )

        XCTAssertEqual(
            MessagingThreadTargetResolver.resolve(
                messageID: root.stableID,
                in: [root]
            ),
            .rootMessageID("root-server")
        )
        XCTAssertEqual(
            MessagingThreadTargetResolver.resolve(
                messageID: "root-server",
                in: [root]
            ),
            .rootMessageID("root-server")
        )
    }

    func testReplyResolvesToItsRootInsteadOfItself() {
        let root = self.message(
            objectID: "root-server",
            clientMessageID: "root-client"
        )
        let reply = self.message(
            objectID: "reply-server",
            clientMessageID: "reply-client",
            replyToMessageID: "root-server"
        )

        XCTAssertEqual(
            MessagingThreadTargetResolver.resolve(
                messageID: reply.stableID,
                in: [root, reply]
            ),
            .rootMessageID("root-server")
        )
    }

    func testReplyCanResolveRootOutsideLoadedPage() {
        let reply = self.message(
            objectID: "reply-server",
            clientMessageID: "reply-client",
            replyToMessageID: "root-server"
        )

        XCTAssertEqual(
            MessagingThreadTargetResolver.resolve(
                messageID: "reply-server",
                in: [reply]
            ),
            .rootMessageID("root-server")
        )
    }

    func testMalformedNestedReplyIsRejected() {
        let root = self.message(
            objectID: "root-server",
            clientMessageID: "root-client"
        )
        let firstReply = self.message(
            objectID: "reply-server",
            clientMessageID: "reply-client",
            replyToMessageID: "root-server"
        )
        let nestedReply = self.message(
            objectID: "nested-server",
            clientMessageID: "nested-client",
            replyToMessageID: "reply-server"
        )

        XCTAssertEqual(
            MessagingThreadTargetResolver.resolve(
                messageID: nestedReply.stableID,
                in: [root, firstReply, nestedReply]
            ),
            .nestedReply(parentMessageID: "reply-server")
        )
    }

    func testUnknownMessageIsNotResolved() {
        XCTAssertEqual(
            MessagingThreadTargetResolver.resolve(
                messageID: "missing",
                in: []
            ),
            .targetNotFound
        )
    }

    private func message(
        objectID: String?,
        clientMessageID: String,
        replyToMessageID: String? = nil
    ) -> MessagingMessageSnapshot {
        MessagingMessageSnapshot(
            objectID: objectID,
            clientMessageID: clientMessageID,
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: Date(timeIntervalSince1970: 1),
            content: MessagingMessageContent(kind: .text, text: clientMessageID),
            replyToMessageID: replyToMessageID,
            deliveryKind: .respectful,
            localState: .confirmed
        )
    }
}
