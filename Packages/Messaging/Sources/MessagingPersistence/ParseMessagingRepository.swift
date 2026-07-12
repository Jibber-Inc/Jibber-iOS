//
//  ParseMessagingRepository.swift
//  MessagingPersistence
//

import Foundation
import MessagingContracts
import ParseSwift

/// Parse-native repository used after authentication has been bridged into
/// ParseSwift. Server triggers remain authoritative for membership, actor
/// identity, ACLs, field allow-lists, and derived timestamps.
public final class ParseMessagingRepository:
    MessagingCapabilitiesRepository,
    MessagingConversationRepository,
    MessagingMessageRepository,
    MessagingMembershipRepository
{
    private let authenticatedUserID: MessagingUserID
    private weak var uploadCache: ParseMessagingAttachmentUploadCaching?

    public init(
        authenticatedUserID: MessagingUserID,
        uploadCache: ParseMessagingAttachmentUploadCaching? = nil
    ) {
        self.authenticatedUserID = authenticatedUserID
        self.uploadCache = uploadCache
    }

    public func capabilities() async throws -> MessagingCapabilities {
        try await GetCapabilitiesCall().runFunction()
    }

    // MARK: Conversations

    public func conversations(
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingConversationSnapshot> {
        let memberships = try await ParseMessagingQueryFactory
            .activeMemberships(userID: authenticatedUserID)
            .findAll(batchLimit: 100)
        let conversationIDs = Array(Set(memberships.compactMap { $0.conversation?.objectId }))
        guard !conversationIDs.isEmpty else {
            return MessagingPage(items: [], nextCursor: nil, hasMore: false)
        }
        let objects = try await ParseMessagingQueryFactory
            .conversations(ids: conversationIDs, before: cursor, pageSize: pageSize)
            .find()
        return try ParseMessagingPageMapper.conversations(objects, pageSize: pageSize)
    }

    public func conversation(
        id: MessagingConversationID
    ) async throws -> MessagingConversationSnapshot {
        let object = try await Pointer<MessagingParseConversation>(objectId: id).fetch()
        return try object.snapshot()
    }

    public func createConversation(
        memberIDs: [MessagingUserID],
        type: MessagingConversationKind,
        title: String? = nil,
        clientConversationID: String = UUID().uuidString.lowercased(),
        contextKey: String? = nil
    ) async throws -> MessagingConversationSnapshot {
        let object = try await CreateConversationCall(
            memberIds: Array(Set(memberIDs)),
            type: type,
            title: title,
            clientConversationId: clientConversationID,
            contextKey: contextKey
        ).runFunction()
        return try object.snapshot()
    }

    // MARK: Memberships

    public func members(
        conversationID: MessagingConversationID
    ) async throws -> [MessagingMemberSnapshot] {
        try await members(conversationIDs: [conversationID])
    }

    public func members(
        conversationIDs: [MessagingConversationID]
    ) async throws -> [MessagingMemberSnapshot] {
        guard !conversationIDs.isEmpty else { return [] }
        let objects = try await ParseMessagingQueryFactory
            .members(conversationIDs: conversationIDs)
            .findAll(batchLimit: 100)
        return try objects
            .map { try $0.snapshot() }
            .sorted { lhs, rhs in
                if lhs.joinedAt == rhs.joinedAt { return lhs.objectID < rhs.objectID }
                return lhs.joinedAt < rhs.joinedAt
            }
    }

    // MARK: Messages

    public func messages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        let objects = try await ParseMessagingQueryFactory
            .messages(conversationID: conversationID, before: cursor, pageSize: pageSize)
            .find()
        let hydrated = try await hydrate(objects)
        return try MessagingPageBuilder.messages(
            hydrated,
            conversationID: conversationID,
            pageSize: pageSize
        )
    }

    public func replies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) async throws -> MessagingPage<MessagingMessageSnapshot> {
        let objects = try await ParseMessagingQueryFactory
            .replies(messageID: messageID, before: cursor, pageSize: pageSize)
            .find()
        let hydrated = try await hydrate(objects)
        return try MessagingPageBuilder.replies(
            hydrated,
            messageID: messageID,
            pageSize: pageSize
        )
    }

    public func pinnedMessages(
        conversationID: MessagingConversationID
    ) async throws -> [MessagingMessageSnapshot] {
        let objects = try await ParseMessagingQueryFactory
            .pinnedMessages(conversationID: conversationID)
            .find()
        return try await hydrate(objects)
    }

    public func perform(
        _ mutation: MessagingMutation,
        idempotencyKey: String
    ) async throws -> MessagingMutationResult {
        switch mutation {
        case .send(let draft, let authorID):
            guard idempotencyKey == draft.clientMessageID else {
                throw ParseMessagingRepositoryError.idempotencyKeyMismatch
            }
            guard authorID == authenticatedUserID else {
                throw MessagingModelError.identityMismatch(
                    expected: authenticatedUserID,
                    actual: authorID
                )
            }
            return .message(try await send(draft))

        case .setConversationTitle(let conversationID, let title):
            let conversation = try await Pointer<MessagingParseConversation>(
                objectId: conversationID
            ).fetch()
            if conversation.title != title {
                _ = try await conversation.operation
                    .set(("title", \MessagingParseConversation.title), to: title)
                    .save()
            }
            return .conversation(try await self.conversation(id: conversationID))

        case .setConversationDeleted(let conversationID, let isDeleted, _):
            guard isDeleted else {
                throw ParseMessagingRepositoryError.clientConversationRestoreDenied
            }
            let conversation = try await Pointer<MessagingParseConversation>(
                objectId: conversationID
            ).fetch()
            if conversation.isDeleted != true {
                _ = try await conversation.operation
                    .set(("isDeleted", \MessagingParseConversation.isDeleted), to: true)
                    .save()
            }
            return .conversation(try await self.conversation(id: conversationID))

        case .setMemberActive(let conversationID, let userID, let active):
            return .member(try await setMemberActive(
                conversationID: conversationID,
                userID: userID,
                active: active
            ))

        case .setMemberHidden(let conversationID, let memberID, let isHidden):
            let member = try await Pointer<MessagingParseConversationMember>(
                objectId: memberID
            ).fetch()
            guard member.conversation?.objectId == conversationID,
                  member.user?.objectId == authenticatedUserID else {
                throw ParseMessagingRepositoryError.membershipIdentityMismatch
            }
            let updated = try await SetConversationHiddenCall(
                conversationId: conversationID,
                isHidden: isHidden
            ).runFunction()
            return .member(try updated.snapshot())

        case .edit(_, let messageID, let text, _):
            let message = try await fetchMessage(messageID)
            if message.text != text {
                _ = try await message.operation
                    .set(("text", \MessagingParseMessage.text), to: text)
                    .save()
            }
            return .message(try await hydrate(fetchMessage(messageID)))

        case .delete(_, let messageID, _):
            let message = try await fetchMessage(messageID)
            if message.isDeleted != true {
                _ = try await message.operation
                    .set(("isDeleted", \MessagingParseMessage.isDeleted), to: true)
                    .save()
            }
            return .message(try await hydrate(fetchMessage(messageID)))

        case .setPinned(_, let messageID, let isPinned, _):
            let message = try await fetchMessage(messageID)
            if message.isPinned != isPinned {
                _ = try await message.operation
                    .set(("isPinned", \MessagingParseMessage.isPinned), to: isPinned)
                    .save()
            }
            return .message(try await hydrate(fetchMessage(messageID)))

        case .setReaction(_, let messageID, let type, let isSelected):
            return .message(try await setReaction(
                messageID: messageID,
                type: type,
                isSelected: isSelected
            ))

        case .markRead(_, let messageID, _, _):
            return .message(try await setReceiptState(
                messageID: messageID,
                state: .read
            ))

        case .markUnread(_, let messageID, _):
            return .message(try await markUnread(messageID: messageID))

        case .setTyping(let conversationID, let memberID, let expiresAt):
            if let expiresAt = expiresAt,
               expiresAt > Date().addingTimeInterval(15) {
                throw ParseMessagingRepositoryError.typingExpiryTooFar
            }
            var member = try await Pointer<MessagingParseConversationMember>(objectId: memberID).fetch()
            guard member.conversation?.objectId == conversationID,
                  member.user?.objectId == authenticatedUserID else {
                throw ParseMessagingRepositoryError.membershipIdentityMismatch
            }
            if let expiresAt = expiresAt {
                _ = try await member.operation
                    .forceSet(("typingExpiresAt", \MessagingParseConversationMember.typingExpiresAt), to: expiresAt)
                    .save()
            } else if member.typingExpiresAt != nil {
                _ = try await member.operation
                    .unset(("typingExpiresAt", \MessagingParseConversationMember.typingExpiresAt))
                    .save()
            }
            member = try await Pointer<MessagingParseConversationMember>(objectId: memberID).fetch()
            return .member(try member.snapshot())

        case .addMessageExpression(_, let messageID, let reference):
            try validateExpression(reference)
            let message = try await fetchMessage(messageID)
            _ = try await message.operation
                .addUnique("expressions", objects: [reference])
                .save()
            return .message(try await hydrate(fetchMessage(messageID)))

        case .addConversationExpression(let conversationID, let reference):
            try validateExpression(reference)
            let conversation = try await Pointer<MessagingParseConversation>(
                objectId: conversationID
            ).fetch()
            _ = try await conversation.operation
                .addUnique("expressions", objects: [reference])
                .save()
            return .conversation(try await self.conversation(id: conversationID))
        }
    }

    // MARK: Write helpers

    private func send(_ draft: MessagingMessageDraft) async throws -> MessagingMessageSnapshot {
        if let existing = try? await recoverMessage(
            conversationID: draft.conversationID,
            clientMessageID: draft.clientMessageID
        ) {
            try? uploadCache?.removeUploadedFiles(clientMessageID: draft.clientMessageID)
            return try await hydrate(existing)
        }

        let attachments = try await uploadAttachments(for: draft)
        let parseMessage = MessagingParseMessage(
            draft: draft,
            authorID: authenticatedUserID,
            uploadedAttachments: attachments
        )
        let call = SendMessageCall(message: parseMessage)
        do {
            let saved = try await call.runFunction()
            try? uploadCache?.removeUploadedFiles(clientMessageID: draft.clientMessageID)
            return try await hydrate(saved)
        } catch {
            if let recovered = try? await recoverMessage(
                conversationID: draft.conversationID,
                clientMessageID: draft.clientMessageID
            ) {
                try? uploadCache?.removeUploadedFiles(clientMessageID: draft.clientMessageID)
                return try await hydrate(recovered)
            }
            throw error
        }
    }

    private func recoverMessage(
        conversationID: MessagingConversationID,
        clientMessageID: String
    ) async throws -> MessagingParseMessage {
        guard let object = try await RecoverMessageCall(
            conversationId: conversationID,
            clientMessageId: clientMessageID
        ).runFunction() else {
            throw ParseMessagingRepositoryError.messageNotFoundByClientID
        }
        return object
    }

    private func setReaction(
        messageID: MessagingMessageID,
        type: String,
        isSelected: Bool
    ) async throws -> MessagingMessageSnapshot {
        if isSelected {
            _ = try await AddReactionCall(messageId: messageID, type: type).runFunction()
        } else {
            let message = Pointer<MessagingParseMessage>(objectId: messageID)
            let user = Pointer<MessagingParseUser>(objectId: authenticatedUserID)
            let query = MessagingParseReaction.query(
                "message" == message,
                "user" == user,
                "type" == type
            )
            do {
                let reaction = try await query.first()
                if reaction.isDeleted != true {
                    _ = try await reaction.operation
                        .set(("isDeleted", \MessagingParseReaction.isDeleted), to: true)
                        .save()
                }
            } catch where Self.isVerifiedObjectNotFound(error) {
                // A verified absence is the idempotent success case. Transport,
                // session, and permission errors must reach the outbox worker.
            }
        }
        return try await hydrate(fetchMessage(messageID))
    }

    private func markUnread(
        messageID: MessagingMessageID
    ) async throws -> MessagingMessageSnapshot {
        try await setReceiptState(messageID: messageID, state: .delivered)
    }

    private func setReceiptState(
        messageID: MessagingMessageID,
        state: MessagingReceiptState
    ) async throws -> MessagingMessageSnapshot {
        let messagePointer = Pointer<MessagingParseMessage>(objectId: messageID)
        let userPointer = Pointer<MessagingParseUser>(objectId: authenticatedUserID)
        let receipt = try await MessagingParseReceipt.query(
            "message" == messagePointer,
            "user" == userPointer
        ).first()
        if receipt.state != state {
            _ = try await receipt.operation
                .set(("state", \MessagingParseReceipt.state), to: state)
                .save()
        }
        return try await hydrate(fetchMessage(messageID))
    }

    private func setMemberActive(
        conversationID: MessagingConversationID,
        userID: MessagingUserID,
        active: Bool
    ) async throws -> MessagingMemberSnapshot {
        let conversation = Pointer<MessagingParseConversation>(objectId: conversationID)
        let user = Pointer<MessagingParseUser>(objectId: userID)
        let existing = try? await MessagingParseConversationMember.query(
            "conversation" == conversation,
            "user" == user
        ).first()

        if var member = existing {
            if member.active != active {
                _ = try await member.operation
                    .set(("active", \MessagingParseConversationMember.active), to: active)
                    .save()
            }
            guard let memberID = member.objectId else {
                throw MessagingModelError.missingField(
                    className: MessagingParseConversationMember.className,
                    field: "objectId"
                )
            }
            member = try await Pointer<MessagingParseConversationMember>(
                objectId: memberID
            ).fetch()
            return try member.snapshot()
        }

        guard active else {
            throw ParseMessagingRepositoryError.membershipNotFound
        }
        var member = MessagingParseConversationMember()
        member.conversation = conversation
        member.user = user
        member.role = .member
        member.active = true
        member.notificationsEnabled = true
        return try await member.save().snapshot()
    }

    private func validateExpression(_ reference: MessagingExpressionReference) throws {
        guard reference.authorID == authenticatedUserID else {
            throw MessagingModelError.identityMismatch(
                expected: authenticatedUserID,
                actual: reference.authorID
            )
        }
        guard !reference.expressionID.isEmpty else {
            throw ParseMessagingRepositoryError.invalidExpressionID
        }
    }

    static func isVerifiedObjectNotFound(_ error: Error) -> Bool {
        (error as? ParseError)?.code == .objectNotFound
    }

    // MARK: Attachments

    private func uploadAttachments(
        for draft: MessagingMessageDraft
    ) async throws -> [MessagingParseAttachment] {
        var uploaded: [MessagingParseAttachment] = []
        uploaded.reserveCapacity(draft.content.attachments.count)
        for attachment in draft.content.attachments {
            if attachment.kind == .linkPreview {
                uploaded.append(MessagingParseAttachment(
                    snapshot: attachment,
                    uploadedFile: nil
                ))
                continue
            }
            let file = try await uploadedFile(
                snapshot: attachment,
                clientMessageID: draft.clientMessageID,
                key: attachment.id
            )
            var thumbnail: ParseFile?
            if let thumbnailURL = attachment.thumbnailURL {
                var thumbnailSnapshot = attachment
                thumbnailSnapshot.id = "\(attachment.id)-thumbnail"
                thumbnailSnapshot.localURL = thumbnailURL.isFileURL ? thumbnailURL : nil
                thumbnailSnapshot.remoteURL = thumbnailURL.isFileURL ? nil : thumbnailURL
                thumbnailSnapshot.thumbnailURL = nil
                thumbnail = try await uploadedFile(
                    snapshot: thumbnailSnapshot,
                    clientMessageID: draft.clientMessageID,
                    key: "\(attachment.id):thumbnail"
                )
            }
            uploaded.append(MessagingParseAttachment(
                snapshot: attachment,
                uploadedFile: file,
                uploadedThumbnail: thumbnail
            ))
        }
        return uploaded
    }

    private func uploadedFile(
        snapshot: MessagingAttachmentSnapshot,
        clientMessageID: String,
        key: String
    ) async throws -> ParseFile {
        if let cached = try uploadCache?.uploadedFile(
            clientMessageID: clientMessageID,
            attachmentKey: key
        ) {
            return cached
        }

        let fileName = Self.safeFileName(for: snapshot)
        let pendingFile: ParseFile
        if let localURL = snapshot.localURL {
            pendingFile = ParseFile(name: fileName, localURL: localURL)
        } else if let remoteURL = snapshot.remoteURL {
            pendingFile = ParseFile(name: fileName, cloudURL: remoteURL)
        } else {
            throw ParseMessagingRepositoryError.attachmentHasNoUploadSource(snapshot.id)
        }
        let saved = try await pendingFile.save()
        try uploadCache?.storeUploadedFile(
            saved,
            clientMessageID: clientMessageID,
            attachmentKey: key
        )
        return saved
    }

    private static func safeFileName(for snapshot: MessagingAttachmentSnapshot) -> String {
        let sourceExtension = snapshot.fileName.flatMap { URL(fileURLWithPath: $0).pathExtension }
            ?? snapshot.localURL?.pathExtension
            ?? "bin"
        let sanitizedExtension = sourceExtension
            .filter { $0.isLetter || $0.isNumber }
            .prefix(8)
        let stem = snapshot.id
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            .prefix(24)
        let safeStem = stem.isEmpty ? String(UUID().uuidString.filter(\.isHexDigit).prefix(24)) : String(stem)
        return "\(safeStem).\(sanitizedExtension.isEmpty ? "bin" : String(sanitizedExtension))"
    }

    // MARK: Hydration

    private func fetchMessage(_ messageID: MessagingMessageID) async throws -> MessagingParseMessage {
        try await Pointer<MessagingParseMessage>(objectId: messageID).fetch()
    }

    private func hydrate(
        _ pending: @autoclosure () async throws -> MessagingParseMessage
    ) async throws -> MessagingMessageSnapshot {
        try await hydrate(try await pending())
    }

    private func hydrate(
        _ object: MessagingParseMessage
    ) async throws -> MessagingMessageSnapshot {
        guard object.objectId != nil else {
            return try object.snapshot()
        }
        return try await hydrate([object]).first ?? object.snapshot()
    }

    private func hydrate(
        _ objects: [MessagingParseMessage]
    ) async throws -> [MessagingMessageSnapshot] {
        let messageIDs = objects.compactMap(\.objectId)
        guard !messageIDs.isEmpty else { return try objects.map { try $0.snapshot() } }

        async let reactionObjects = ParseMessagingQueryFactory
            .reactions(messageIDs: messageIDs)
            .findAll(batchLimit: 100)
        async let receiptObjects = ParseMessagingQueryFactory
            .receipts(messageIDs: messageIDs)
            .findAll(batchLimit: 100)
        let reactions = try await reactionObjects.map { try $0.snapshot() }
        let receipts = try await receiptObjects.map { try $0.snapshot() }
        let reactionsByMessage = Dictionary(grouping: reactions, by: \.messageID)
        let receiptsByMessage = Dictionary(grouping: receipts, by: \.messageID)

        return try objects.map { object in
            var snapshot = try object.snapshot()
            if let objectID = object.objectId {
                snapshot.reactions = reactionsByMessage[objectID] ?? []
                snapshot.receipts = receiptsByMessage[objectID] ?? []
            }
            return snapshot
        }
    }
}

// MARK: Cloud function payloads

private struct GetCapabilitiesCall: ParseCloudable, Sendable {
    typealias ReturnType = MessagingCapabilities
    var functionJobName: String { get { "messagingGetCapabilities" } set {} }
}

private struct CreateConversationCall: ParseCloudable, Sendable {
    typealias ReturnType = MessagingParseConversation
    var functionJobName: String { get { "messagingCreateConversation" } set {} }
    let memberIds: [MessagingUserID]
    let type: MessagingConversationKind
    let title: String?
    let clientConversationId: String
    let contextKey: String?
}

private struct SendMessageCall: ParseCloudable, Sendable {
    typealias ReturnType = MessagingParseMessage
    var functionJobName: String { get { "messagingSendMessage" } set {} }
    let conversationId: MessagingConversationID
    let clientMessageId: String
    let clientCreatedAt: Date?
    let contentType: MessagingContentKind?
    let text: String?
    let linkURL: String?
    let attachments: [MessagingParseAttachment]?
    let expressions: [MessagingExpressionReference]?
    let metadata: [String: String]?
    let replyToId: MessagingMessageID?
    let deliveryType: MessagingDeliveryKind?

    init(message: MessagingParseMessage) {
        conversationId = message.conversation?.objectId ?? ""
        clientMessageId = message.clientMessageId ?? ""
        clientCreatedAt = message.clientCreatedAt
        contentType = message.contentType
        text = message.text
        linkURL = message.linkURL
        attachments = message.attachments
        expressions = message.expressions
        metadata = message.metadata
        replyToId = message.replyTo?.objectId
        deliveryType = message.deliveryType
    }
}

private struct RecoverMessageCall: ParseCloudable, Sendable {
    typealias ReturnType = MessagingParseMessage?
    var functionJobName: String { get { "messagingGetMessageByClientId" } set {} }
    let conversationId: MessagingConversationID
    let clientMessageId: String
}

private struct AddReactionCall: ParseCloudable, Sendable {
    typealias ReturnType = MessagingParseReaction
    var functionJobName: String { get { "messagingAddReaction" } set {} }
    let messageId: MessagingMessageID
    let type: String
}

private struct SetConversationHiddenCall: ParseCloudable, Sendable {
    typealias ReturnType = MessagingParseConversationMember
    var functionJobName: String { get { "messagingSetConversationHidden" } set {} }
    let conversationId: MessagingConversationID
    let isHidden: Bool
}

public enum ParseMessagingRepositoryError: Error, Equatable {
    case attachmentHasNoUploadSource(String)
    case clientConversationRestoreDenied
    case idempotencyKeyMismatch
    case invalidExpressionID
    case membershipIdentityMismatch
    case membershipNotFound
    case messageNotFoundByClientID
    case typingExpiryTooFar
}

public struct ParseMessagingErrorClassifier: MessagingErrorClassifying {
    public init() {}

    public func isRetryableMessagingError(_ error: Error) -> Bool {
        if let error = error as? ParseError {
            switch error.code {
            case .connectionFailed,
                 .internalServer,
                 .timeout,
                 .requestLimitExceeded,
                 .fileSaveFailure,
                 .duplicateValue,
                 .duplicateRequest:
                return true
            default:
                return false
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// True only when the server has positively denied or invalidated access.
    /// Callers use this as a local-cache privacy boundary; ordinary validation
    /// errors are terminal but do not claim that prior access was revoked.
    public func isMessagingAccessRevokedError(_ error: Error) -> Bool {
        guard let error = error as? ParseError else { return false }
        switch error.code {
        case .objectNotFound,
             .operationForbidden,
             .invalidSessionToken,
             .userCannotBeAlteredWithoutSession:
            return true
        default:
            return false
        }
    }
}
