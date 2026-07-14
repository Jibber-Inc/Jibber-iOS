import XCTest
@testable import MessagingContracts

final class MessagingContractsTests: XCTestCase {
    func testCapabilitiesDecodeIgnoresFutureServerFields() throws {
        let data = Data(
            """
            {
              "available": true,
              "minimumAppVersion": "2.4.0",
              "schemaVersion": 1,
              "features": { "liveQuery": true, "offlineIdempotency": true },
              "futureField": { "safe": true }
            }
            """.utf8
        )

        let capabilities = try JSONDecoder().decode(MessagingCapabilities.self, from: data)

        XCTAssertTrue(capabilities.available)
        XCTAssertEqual(capabilities.minimumAppVersion, "2.4.0")
        XCTAssertEqual(capabilities.schemaVersion, MessagingCapabilities.supportedSchemaVersion)
        XCTAssertEqual(capabilities.features["liveQuery"], true)
    }

    func testLegacyMemberCacheDefaultsToVisible() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(
            """
            {
              "objectID": "member-1",
              "conversationID": "conversation-1",
              "userID": "user-1",
              "role": "member",
              "joinedAt": "2026-07-11T00:00:00Z",
              "active": true,
              "notificationsEnabled": true,
              "unreadCount": 0
            }
            """.utf8
        )

        let member = try decoder.decode(MessagingMemberSnapshot.self, from: data)

        XCTAssertFalse(member.isHidden)
        XCTAssertNil(member.hiddenAt)
    }

    func testCursorRoundTripAndScopeValidation() throws {
        let cursor = MessagingCursor.messages(
            conversationID: "conversation-1",
            sortDate: Date(timeIntervalSince1970: 1234.5),
            stableID: "message-9"
        )

        let encoded = try MessagingCursorCodec.encode(cursor)
        let decoded = try MessagingCursorCodec.decode(encoded)

        XCTAssertEqual(decoded, cursor)
        XCTAssertThrowsError(
            try MessagingCursorCodec.validate(decoded, expectedScope: "messages:conversation-2")
        )
    }

    func testMessagePageUsesDeterministicLastItemCursor() throws {
        let messages = (0..<3).map { index in
            MessagingMessageSnapshot(
                objectID: "object-\(index)",
                clientMessageID: "client-\(index)",
                conversationID: "conversation-1",
                authorID: "user-1",
                clientCreatedAt: Date(timeIntervalSince1970: TimeInterval(100 - index)),
                serverCreatedAt: Date(timeIntervalSince1970: TimeInterval(100 - index)),
                content: MessagingMessageContent(kind: .text, text: "Message \(index)"),
                deliveryKind: .conversational,
                localState: .confirmed
            )
        }

        let page = try MessagingPageBuilder.messages(
            messages,
            conversationID: "conversation-1",
            pageSize: 2
        )

        XCTAssertEqual(page.items.count, 2)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextCursor?.stableID, "object-1")
    }

    func testPartialReplyPreviewFetchesAuthoritativePageBeforeDeclaringExhaustion() {
        XCTAssertTrue(MessagingReplyPaginationState.shouldFetchPreviousPage(
            hasCachedReplies: true,
            hasCursor: false,
            hasAuthoritativePage: false
        ))
        XCTAssertFalse(MessagingReplyPaginationState.shouldFetchPreviousPage(
            hasCachedReplies: true,
            hasCursor: false,
            hasAuthoritativePage: true
        ))
        XCTAssertTrue(MessagingReplyPaginationState.shouldFetchPreviousPage(
            hasCachedReplies: true,
            hasCursor: true,
            hasAuthoritativePage: true
        ))
    }

    func testMessageIdentityRemainsClientIDAfterConfirmation() {
        var message = MessagingMessageSnapshot(
            clientMessageID: "client-1",
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: Date(),
            content: MessagingMessageContent(kind: .text, text: "Hello"),
            deliveryKind: .respectful,
            localState: .queued
        )
        let optimisticID = message.id
        message.objectID = "server-1"
        message.localState = .confirmed

        XCTAssertEqual(message.id, optimisticID)
        XCTAssertEqual(message.canonicalMessageID, "server-1")
    }

    func testThreadRootMessageIDUsesParentForReplyAndSelfForRoot() {
        var message = MessagingMessageSnapshot(
            objectID: "server-1",
            clientMessageID: "client-1",
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: Date(),
            content: MessagingMessageContent(kind: .text, text: "Hello"),
            deliveryKind: .respectful,
            localState: .confirmed
        )

        XCTAssertEqual(message.threadRootMessageID, "server-1")

        message.replyToMessageID = "root-1"
        XCTAssertEqual(message.threadRootMessageID, "root-1")
    }

    func testNotificationReplyIdempotencyIsStableAndActorScoped() {
        let first = MessagingIdempotencyKey.notificationReply(
            userID: "user-1",
            conversationID: "conversation-1",
            messageID: "message-1",
            actionID: "quick"
        )
        let duplicate = MessagingIdempotencyKey.notificationReply(
            userID: "user-1",
            conversationID: "conversation-1",
            messageID: "message-1",
            actionID: "quick"
        )
        let otherMember = MessagingIdempotencyKey.notificationReply(
            userID: "user-2",
            conversationID: "conversation-1",
            messageID: "message-1",
            actionID: "quick"
        )

        XCTAssertEqual(first, duplicate)
        XCTAssertNotEqual(first, otherMember)
        XCTAssertTrue(first.hasPrefix("notification.reply."))
    }

    func testDeletingOnlyReplyDropsSummaryCountToZero() {
        var onlyReply = makeReply(
            objectID: "reply-only",
            clientCreatedAt: Date(timeIntervalSince1970: 200)
        )
        onlyReply.isDeleted = true
        onlyReply.deletedAt = Date(timeIntervalSince1970: 300)

        XCTAssertEqual(
            MessagingReplySummary.totalCount(
                authoritativeCount: 0,
                loadedReplies: [onlyReply]
            ),
            0
        )
        XCTAssertNil(MessagingReplySummary.latestActiveReply(in: [onlyReply]))
    }

    func testDeletingNewestReplySurfacesNextActivePreview() throws {
        let olderReply = makeReply(
            objectID: "reply-older",
            clientCreatedAt: Date(timeIntervalSince1970: 100)
        )
        var newestReply = makeReply(
            objectID: "reply-newest",
            clientCreatedAt: Date(timeIntervalSince1970: 200)
        )
        newestReply.isDeleted = true
        newestReply.deletedAt = Date(timeIntervalSince1970: 300)

        let loadedReplies = [newestReply, olderReply]
        XCTAssertEqual(
            MessagingReplySummary.totalCount(
                authoritativeCount: 1,
                loadedReplies: loadedReplies
            ),
            1
        )
        XCTAssertEqual(
            try XCTUnwrap(MessagingReplySummary.latestActiveReply(in: loadedReplies)).objectID,
            "reply-older"
        )
    }

    func testReplyPreviewFollowsLatestPointerAndClearsAfterLastDeletion() throws {
        let olderReply = makeReply(
            objectID: "reply-older",
            clientCreatedAt: Date(timeIntervalSince1970: 100)
        )
        let newestReply = makeReply(
            objectID: "reply-newest",
            clientCreatedAt: Date(timeIntervalSince1970: 200)
        )
        var root = MessagingMessageSnapshot(
            objectID: "root-1",
            clientMessageID: "client-root-1",
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: Date(timeIntervalSince1970: 50),
            content: MessagingMessageContent(kind: .text, text: "Root"),
            replyCount: 2,
            latestReplyID: "reply-newest",
            deliveryKind: .respectful,
            localState: .confirmed
        )

        XCTAssertEqual(
            MessagingReplyPreviewResolver.replies(
                for: root,
                from: [olderReply, newestReply]
            ).map(\.objectID),
            ["reply-newest"]
        )

        root.replyCount = 1
        root.latestReplyID = "reply-older"
        XCTAssertEqual(
            MessagingReplyPreviewResolver.replies(
                for: root,
                from: [newestReply, olderReply]
            ).map(\.objectID),
            ["reply-older"]
        )

        root.replyCount = 0
        root.latestReplyID = nil
        XCTAssertTrue(MessagingReplyPreviewResolver.replies(
            for: root,
            from: [newestReply, olderReply]
        ).isEmpty)
    }

    func testLegacyMessageSnapshotDecodesWithoutLatestReplySummary() throws {
        let legacy = MessagingMessageSnapshot(
            objectID: "root-legacy",
            clientMessageID: "client-root-legacy",
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: Date(timeIntervalSince1970: 50),
            content: MessagingMessageContent(kind: .text, text: "Root"),
            replyCount: 1,
            deliveryKind: .respectful,
            localState: .confirmed
        )

        let decoded = try JSONDecoder().decode(
            MessagingMessageSnapshot.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertNil(decoded.latestReplyID)
        XCTAssertNil(decoded.latestReplyAt)
        XCTAssertNil(decoded.latestReplyAuthorID)
        XCTAssertNil(decoded.latestReplyText)
    }

    private func makeReply(
        objectID: String,
        clientCreatedAt: Date
    ) -> MessagingMessageSnapshot {
        MessagingMessageSnapshot(
            objectID: objectID,
            clientMessageID: "client-\(objectID)",
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: clientCreatedAt,
            serverCreatedAt: clientCreatedAt,
            content: MessagingMessageContent(kind: .text, text: objectID),
            replyToMessageID: "root-1",
            deliveryKind: .respectful,
            localState: .confirmed
        )
    }
}
