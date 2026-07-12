import XCTest
import MessagingContracts
@testable import MessagingPersistence

final class MessagingRealtimeReconcilerTests: XCTestCase {
    func testMessageEditAndDeletePreserveHydratedReactionAndReceiptState() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let reaction = MessagingReactionSnapshot(
            objectID: "reaction-1",
            messageID: "message-1",
            userID: "user-2",
            type: "heart",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let receipt = MessagingReceiptSnapshot(
            objectID: "receipt-1",
            messageID: "message-1",
            userID: "user-2",
            state: .read,
            occurredAt: Date(timeIntervalSince1970: 101)
        )
        var local = makeMessage(text: "Before", updatedAt: 100)
        local.reactions = [reaction]
        local.receipts = [receipt]
        try store.upsert(messages: [local])
        let reconciler = MessagingRealtimeReconciler(store: store)

        var edited = makeMessage(text: "After", updatedAt: 102)
        edited.reactions = []
        edited.receipts = []
        try reconciler.apply(.messageUpserted(edited))

        var cached = try XCTUnwrap(store.cachedMessage(objectID: "message-1"))
        XCTAssertEqual(cached.content.text, "After")
        XCTAssertEqual(cached.reactions, [reaction])
        XCTAssertEqual(cached.receipts, [receipt])

        var deleted = makeMessage(text: "After", updatedAt: 103)
        deleted.isDeleted = true
        try reconciler.apply(.messageDeleted(deleted))

        cached = try XCTUnwrap(store.cachedMessage(objectID: "message-1"))
        XCTAssertTrue(cached.isDeleted)
        XCTAssertEqual(cached.reactions, [reaction])
        XCTAssertEqual(cached.receipts, [receipt])
    }

    func testRelatedEventsArrivingBeforeMessageAreAppliedWhenMessageAppears() throws {
        let store = try GRDBMessagingStore(inMemory: .init())
        let reconciler = MessagingRealtimeReconciler(store: store)
        let reaction = MessagingReactionSnapshot(
            objectID: "reaction-early",
            messageID: "message-1",
            userID: "user-2",
            type: "thumbs-up",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let receipt = MessagingReceiptSnapshot(
            objectID: "receipt-early",
            messageID: "message-1",
            userID: "user-3",
            state: .delivered,
            occurredAt: Date(timeIntervalSince1970: 101)
        )

        try reconciler.apply(.reactionUpserted(reaction))
        try reconciler.apply(.receiptUpserted(receipt))
        try reconciler.apply(.messageUpserted(makeMessage(text: "Hello", updatedAt: 102)))

        let cached = try XCTUnwrap(store.cachedMessage(objectID: "message-1"))
        XCTAssertEqual(cached.reactions, [reaction])
        XCTAssertEqual(cached.receipts, [receipt])
    }

    func testReconnectCatchUpIsConsumedExactlyOnce() {
        var tracker = MessagingRealtimeCatchUpTracker()

        XCTAssertFalse(tracker.consumeCatchUpOnConnected())
        tracker.disconnected()
        XCTAssertTrue(tracker.isCatchUpRequired)
        XCTAssertTrue(tracker.consumeCatchUpOnConnected())
        XCTAssertFalse(tracker.isCatchUpRequired)
        XCTAssertFalse(tracker.consumeCatchUpOnConnected())
    }

    private func makeMessage(
        text: String,
        updatedAt: TimeInterval
    ) -> MessagingMessageSnapshot {
        MessagingMessageSnapshot(
            objectID: "message-1",
            clientMessageID: "client-1",
            conversationID: "conversation-1",
            authorID: "user-1",
            clientCreatedAt: Date(timeIntervalSince1970: 90),
            serverCreatedAt: Date(timeIntervalSince1970: 91),
            serverUpdatedAt: Date(timeIntervalSince1970: updatedAt),
            content: MessagingMessageContent(kind: .text, text: text),
            deliveryKind: .conversational,
            localState: .confirmed
        )
    }
}
