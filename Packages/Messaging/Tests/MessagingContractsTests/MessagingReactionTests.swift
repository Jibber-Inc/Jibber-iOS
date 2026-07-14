import XCTest
@testable import MessagingContracts

final class MessagingReactionTests: XCTestCase {
    func testSupportedTypesMapToStableParseValues() {
        XCTAssertEqual(
            MessagingReactionType.allCases.map(\.rawValue),
            ["like", "love", "dislike"]
        )
        XCTAssertEqual(makeReaction(userID: "user-1", type: "like").reactionType, .like)
        XCTAssertEqual(makeReaction(userID: "user-1", type: "love").reactionType, .love)
        XCTAssertEqual(makeReaction(userID: "user-1", type: "dislike").reactionType, .dislike)
        XCTAssertNil(makeReaction(userID: "user-1", type: "read").reactionType)
    }

    func testActiveReactionsFilterBothFormsOfTombstone() {
        var deletedFlag = makeReaction(userID: "user-2", type: "love")
        deletedFlag.isDeleted = true
        var deletedDate = makeReaction(userID: "user-3", type: "dislike")
        deletedDate.deletedAt = Date(timeIntervalSince1970: 200)
        let unknownActive = makeReaction(userID: "user-4", type: "future-type")
        let active = makeReaction(userID: "user-1", type: "like")
        var message = makeMessage()
        message.reactions = [deletedFlag, deletedDate, unknownActive, active]

        XCTAssertEqual(message.activeReactions, [unknownActive, active])
    }

    func testReactionGroupsAggregateUniqueUsersAndCurrentSelection() {
        var currentLike = makeReaction(userID: "current", type: "like")
        currentLike.localMutationState = .selecting
        var tombstonedLove = makeReaction(userID: "other-3", type: "love")
        tombstonedLove.isDeleted = true
        var message = makeMessage()
        message.reactions = [
            makeReaction(userID: "other-1", type: "love"),
            currentLike,
            makeReaction(userID: "other-2", type: "like"),
            makeReaction(userID: "other-2", type: "like"),
            tombstonedLove,
            makeReaction(userID: "other-4", type: "future-type")
        ]

        let groups = message.reactionGroups(currentUserID: "current")

        XCTAssertEqual(groups.map(\.type), [.like, .love])
        XCTAssertEqual(groups[0].count, 2)
        XCTAssertEqual(groups[0].userIDs, ["current", "other-2"])
        XCTAssertTrue(groups[0].isSelectedByCurrentUser)
        XCTAssertEqual(groups[0].currentUserMutationState, .selecting)
        XCTAssertEqual(groups[1].count, 1)
        XCTAssertFalse(groups[1].isSelectedByCurrentUser)
        XCTAssertNil(groups[1].currentUserMutationState)
        XCTAssertEqual(message.selectedReactionType(for: "current"), .like)
        XCTAssertNil(message.selectedReactionType(for: "missing"))
    }

    func testTypedReactionMutationKeepsStringWireEncoding() throws {
        let mutation = MessagingMutation.setReaction(
            conversationID: "conversation-1",
            messageID: "message-1",
            type: MessagingReactionType.love,
            isSelected: true
        )

        let data = try JSONEncoder().encode(mutation)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("love"))
        let decoded = try JSONDecoder().decode(MessagingMutation.self, from: data)
        guard case .setReaction(
            let conversationID, let messageID, let type, let isSelected
        ) = decoded else {
            return XCTFail("Expected a setReaction mutation")
        }
        XCTAssertEqual(conversationID, "conversation-1")
        XCTAssertEqual(messageID, "message-1")
        XCTAssertEqual(type, "love")
        XCTAssertTrue(isSelected)
    }

    func testCachedSelectionPlanTogglesOffAndSwitchesUniqueReaction() {
        var message = makeMessage(reactions: [
            makeReaction(userID: "me", type: .like),
        ])

        XCTAssertEqual(
            message.reactionSelectionChanges(toggling: .like, for: "me"),
            [.init(type: .like, isSelected: false)]
        )
        XCTAssertEqual(
            message.reactionSelectionChanges(toggling: .love, for: "me"),
            [.init(type: .love, isSelected: true)]
        )

        message.reactions.append(makeReaction(userID: "me", type: .dislike))
        XCTAssertEqual(
            message.reactionSelectionChanges(toggling: .love, for: "me"),
            [.init(type: .love, isSelected: true)]
        )
    }

    func testFailedReactionExposesExactDurableRetryOperation() {
        var failed = makeReaction(userID: "me", type: .love)
        failed.localMutationID = "reaction-operation-1"
        failed.localMutationState = .selectionFailed
        let message = makeMessage(reactions: [failed])

        XCTAssertEqual(
            message.failedReactionMutationID(type: .love, for: "me"),
            "reaction-operation-1"
        )
        XCTAssertNil(message.failedReactionMutationID(type: .like, for: "me"))
    }

    func testLegacyReactionPayloadDefaultsLocalMutationFieldsToNil() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(
            """
            {
              "messageID": "message-1",
              "userID": "user-1",
              "type": "like",
              "createdAt": "2026-07-13T00:00:00Z",
              "isDeleted": false
            }
            """.utf8
        )

        let reaction = try decoder.decode(MessagingReactionSnapshot.self, from: data)

        XCTAssertNil(reaction.localMutationID)
        XCTAssertNil(reaction.localMutationState)
        XCTAssertNil(reaction.lastFailureDescription)
        XCTAssertTrue(reaction.isActive)
    }

    private func makeReaction(
        userID: MessagingUserID,
        type: String
    ) -> MessagingReactionSnapshot {
        MessagingReactionSnapshot(
            objectID: "reaction-\(userID)-\(type)",
            messageID: "message-1",
            userID: userID,
            type: type,
            createdAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func makeReaction(
        userID: MessagingUserID,
        type: MessagingReactionType
    ) -> MessagingReactionSnapshot {
        makeReaction(userID: userID, type: type.rawValue)
    }

    private func makeMessage(
        reactions: [MessagingReactionSnapshot] = []
    ) -> MessagingMessageSnapshot {
        MessagingMessageSnapshot(
            objectID: "message-1",
            clientMessageID: "client-1",
            conversationID: "conversation-1",
            authorID: "author-1",
            clientCreatedAt: Date(timeIntervalSince1970: 90),
            content: MessagingMessageContent(kind: .text, text: "Hello"),
            deliveryKind: .conversational,
            reactions: reactions,
            localState: .confirmed
        )
    }
}
