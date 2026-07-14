import XCTest
import MessagingContracts
import ParseSwift
@testable import MessagingPersistence

final class ParseMessagingModelsTests: XCTestCase {
    func testParseClassNamesMatchBackendSchema() {
        XCTAssertEqual(MessagingParseConversation.className, "Conversation")
        XCTAssertEqual(MessagingParseConversationMember.className, "ConversationMember")
        XCTAssertEqual(MessagingParseMessage.className, "Message")
        XCTAssertEqual(MessagingParseReaction.className, "MessageReaction")
        XCTAssertEqual(MessagingParseReceipt.className, "MessageReceipt")
    }

    func testOutgoingMessageUsesCanonicalPointersAndIdempotencyKey() {
        let draft = MessagingMessageDraft(
            conversationID: "conversation-1",
            clientMessageID: "client-1",
            clientCreatedAt: Date(timeIntervalSince1970: 100),
            content: MessagingMessageContent(kind: .text, text: "Hello"),
            deliveryKind: .timeSensitive
        )

        let object = MessagingParseMessage(
            draft: draft,
            authorID: "user-1",
            uploadedAttachments: []
        )

        XCTAssertEqual(object.conversation?.objectId, "conversation-1")
        XCTAssertEqual(object.author?.objectId, "user-1")
        XCTAssertEqual(object.clientMessageId, "client-1")
        XCTAssertEqual(object.isDeleted, false)
        XCTAssertEqual(object.isPinned, false)
    }

    func testOutgoingMessageUsesTopLevelLinkAndMetadataWireFields() throws {
        let draft = MessagingMessageDraft(
            conversationID: "conversation-1",
            clientMessageID: "client-link-1",
            content: MessagingMessageContent(
                kind: .link,
                text: "Example",
                linkURL: URL(string: "https://example.com/path")!,
                attributes: ["source": "share-extension"]
            )
        )

        let object = MessagingParseMessage(
            draft: draft,
            authorID: "user-1",
            uploadedAttachments: []
        )
        XCTAssertEqual(object.linkURL, "https://example.com/path")
        XCTAssertEqual(object.metadata, ["source": "share-extension"])

        let json = String(data: try JSONEncoder().encode(object), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"linkURL\""))
        XCTAssertTrue(json.contains("\"metadata\""))
        XCTAssertFalse(json.contains("\"attributes\""))
    }

    func testExpressionReferenceUsesBackendCodingKeys() throws {
        let reference = MessagingExpressionReference(
            authorID: "user-1",
            expressionID: "smile"
        )
        let json = String(data: try JSONEncoder().encode(reference), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"authorId\""))
        XCTAssertTrue(json.contains("\"expressionId\""))
        XCTAssertFalse(json.contains("authorID"))
    }

    func testAttachmentSnapshotDerivesStableIDWhenServerOmitsAttachmentID() throws {
        let url = URL(string: "https://parsefiles.back4app.com/app/maya-image.png")!
        let file = try JSONDecoder().decode(
            ParseFile.self,
            from: Data(
                """
                {
                  "__type": "File",
                  "name": "maya-image.png",
                  "url": "\(url.absoluteString)"
                }
                """.utf8
            )
        )
        let attachment = MessagingParseAttachment(
            kind: .image,
            file: file,
            fileName: "maya-image.png",
            mimeType: "image/png",
            byteCount: 1234
        )

        let snapshot = try attachment.snapshot()

        XCTAssertEqual(snapshot.id, url.absoluteString)
        XCTAssertEqual(snapshot.kind, .image)
        XCTAssertEqual(snapshot.remoteURL, url)
        XCTAssertEqual(snapshot.fileName, "maya-image.png")
        XCTAssertEqual(snapshot.mimeType, "image/png")
        XCTAssertEqual(snapshot.byteCount, 1234)
    }

    func testRelatedSnapshotsCarryParseUpdateTimestamps() throws {
        let updatedAt = Date(timeIntervalSince1970: 300)
        var reaction = MessagingParseReaction()
        reaction.objectId = "reaction-1"
        reaction.createdAt = Date(timeIntervalSince1970: 100)
        reaction.updatedAt = updatedAt
        reaction.message = Pointer<MessagingParseMessage>(objectId: "message-1")
        reaction.user = Pointer<MessagingParseUser>(objectId: "user-1")
        reaction.type = "heart"

        var receipt = MessagingParseReceipt()
        receipt.objectId = "receipt-1"
        receipt.createdAt = Date(timeIntervalSince1970: 100)
        receipt.updatedAt = updatedAt
        receipt.message = Pointer<MessagingParseMessage>(objectId: "message-1")
        receipt.user = Pointer<MessagingParseUser>(objectId: "user-1")
        receipt.state = .read
        receipt.readAt = Date(timeIntervalSince1970: 250)

        var member = MessagingParseConversationMember()
        member.objectId = "member-1"
        member.updatedAt = updatedAt
        member.conversation = Pointer<MessagingParseConversation>(objectId: "conversation-1")
        member.user = Pointer<MessagingParseUser>(objectId: "user-1")
        member.role = .member
        member.joinedAt = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(try reaction.snapshot().serverUpdatedAt, updatedAt)
        XCTAssertEqual(try receipt.snapshot().serverUpdatedAt, updatedAt)
        XCTAssertEqual(try member.snapshot().serverUpdatedAt, updatedAt)
    }

    func testCacheFallbackAndReactionAbsenceUseNarrowParseErrorClasses() throws {
        let objectNotFound = try parseError(code: 101)
        let permissionDenied = try parseError(code: 119)
        let invalidSession = try parseError(code: 209)
        let connectionFailure = try parseError(code: 100)
        let invalidQuery = try parseError(code: 102)
        let classifier = ParseMessagingErrorClassifier()

        XCTAssertTrue(classifier.isMessagingAccessRevokedError(objectNotFound))
        XCTAssertTrue(classifier.isMessagingAccessRevokedError(permissionDenied))
        XCTAssertTrue(classifier.isMessagingAccessRevokedError(invalidSession))
        XCTAssertFalse(classifier.isMessagingAccessRevokedError(connectionFailure))
        XCTAssertTrue(classifier.isRetryableMessagingError(connectionFailure))
        XCTAssertFalse(classifier.isRetryableMessagingError(invalidQuery))

        XCTAssertTrue(ParseMessagingRepository.isVerifiedObjectNotFound(objectNotFound))
        XCTAssertFalse(ParseMessagingRepository.isVerifiedObjectNotFound(connectionFailure))
        XCTAssertFalse(ParseMessagingRepository.isVerifiedObjectNotFound(permissionDenied))
    }

    private func parseError(code: Int) throws -> ParseError {
        try JSONDecoder().decode(
            ParseError.self,
            from: Data("{\"code\":\(code),\"error\":\"test\"}".utf8)
        )
    }
}
