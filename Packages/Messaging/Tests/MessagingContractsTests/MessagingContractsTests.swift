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
}
