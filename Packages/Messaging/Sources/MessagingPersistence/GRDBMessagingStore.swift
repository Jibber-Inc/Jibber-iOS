//
//  GRDBMessagingStore.swift
//  MessagingPersistence
//

import Foundation
import GRDB
import MessagingContracts
import ParseSwift

/// Durable, transactionally consistent cache and outbox. A send is staged in
/// the message cache and outbox in the same SQLite transaction, so process
/// termination cannot leave an optimistic bubble without its retry operation.
public final class GRDBMessagingStore: MessagingLocalStore {
    public struct Limits: Hashable {
        public var conversations: Int
        public var messagesPerConversation: Int

        public init(conversations: Int = 500, messagesPerConversation: Int = 2_000) {
            self.conversations = max(1, conversations)
            self.messagesPerConversation = max(1, messagesPerConversation)
        }
    }

    private let databaseQueue: DatabaseQueue
    private let limits: Limits

    public init(databaseURL: URL, limits: Limits = Limits()) throws {
        let databaseDirectory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: databaseDirectory,
            withIntermediateDirectories: true
        )
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: databaseDirectory.path
        )
        #endif
        var configuration = Configuration()
        configuration.journalMode = .wal
        configuration.busyMode = .timeout(5)
        databaseQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        self.limits = limits
        try migrate()
        try recoverInterruptedOperations()
    }

    /// Intended for tests and previews.
    public init(inMemory limits: Limits = Limits()) throws {
        databaseQueue = try DatabaseQueue()
        self.limits = limits
        try migrate()
    }

    public static func defaultDatabaseURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw MessagingPersistenceError.applicationSupportDirectoryUnavailable
        }
        return baseURL
            .appendingPathComponent("Messaging", isDirectory: true)
            .appendingPathComponent("messaging.sqlite", isDirectory: false)
    }

    // MARK: MessagingCache

    public func upsert(conversations: [MessagingConversationSnapshot]) throws {
        guard !conversations.isEmpty else { return }
        return try databaseQueue.write { db in
            for conversation in conversations {
                try Self.upsert(conversation: conversation, in: db)
            }
            let prunedIDs = try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM messaging_conversation_cache
                    WHERE NOT EXISTS (
                        SELECT 1 FROM messaging_outbox
                        WHERE messaging_outbox.conversation_id = messaging_conversation_cache.id
                    )
                    ORDER BY sort_date DESC, id DESC
                    LIMIT -1 OFFSET ?
                    """,
                arguments: [limits.conversations]
            )
            for id in prunedIDs {
                try purgeConversation(id: id, in: db)
            }
        }
    }

    public func cachedConversations(
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> MessagingPage<MessagingConversationSnapshot> {
        try Self.validate(pageSize: pageSize)
        if let cursor = cursor {
            try MessagingCursorCodec.validate(
                cursor,
                expectedScope: MessagingCursor.conversationScope
            )
        }
        return try databaseQueue.read { db in
            let rows: [Row]
            if let cursor = cursor {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT payload FROM messaging_conversation_cache
                        WHERE sort_date < ? OR (sort_date = ? AND id < ?)
                        ORDER BY sort_date DESC, id DESC
                        LIMIT ?
                        """,
                    arguments: [
                        cursor.sortDate.timeIntervalSince1970,
                        cursor.sortDate.timeIntervalSince1970,
                        cursor.stableID,
                        pageSize + 1
                    ]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT payload FROM messaging_conversation_cache
                        ORDER BY sort_date DESC, id DESC
                        LIMIT ?
                        """,
                    arguments: [pageSize + 1]
                )
            }
            let values: [MessagingConversationSnapshot] = try rows.map {
                try Self.decode(MessagingConversationSnapshot.self, from: $0["payload"])
            }
            return try MessagingPageBuilder.conversations(values, pageSize: pageSize)
        }
    }

    public func upsert(messages: [MessagingMessageSnapshot]) throws {
        guard !messages.isEmpty else { return }
        try databaseQueue.write { db in
            let conversationIDs = Set(messages.map(\.conversationID))
            for message in messages {
                try Self.upsert(message: message, in: db)
            }
            for conversationID in conversationIDs {
                try pruneMessages(conversationID: conversationID, in: db)
            }
        }
    }

    public func cachedMessages(
        conversationID: MessagingConversationID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> MessagingPage<MessagingMessageSnapshot> {
        try Self.validate(pageSize: pageSize)
        let scope = MessagingCursor.messageScope(conversationID: conversationID)
        if let cursor = cursor {
            try MessagingCursorCodec.validate(cursor, expectedScope: scope)
        }
        return try databaseQueue.read { db in
            let rows: [Row]
            if let cursor = cursor {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT payload FROM messaging_message_cache
                        WHERE conversation_id = ?
                          AND reply_to_id IS NULL
                          AND (sort_date < ? OR (sort_date = ? AND sort_id < ?))
                        ORDER BY sort_date DESC, sort_id DESC
                        LIMIT ?
                        """,
                    arguments: [
                        conversationID,
                        cursor.sortDate.timeIntervalSince1970,
                        cursor.sortDate.timeIntervalSince1970,
                        cursor.stableID,
                        pageSize + 1
                    ]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT payload FROM messaging_message_cache
                        WHERE conversation_id = ?
                          AND reply_to_id IS NULL
                        ORDER BY sort_date DESC, sort_id DESC
                        LIMIT ?
                        """,
                    arguments: [conversationID, pageSize + 1]
                )
            }
            let values: [MessagingMessageSnapshot] = try rows.map {
                try Self.decode(MessagingMessageSnapshot.self, from: $0["payload"])
            }
            return try MessagingPageBuilder.messages(
                values,
                conversationID: conversationID,
                pageSize: pageSize
            )
        }
    }

    public func cachedReplies(
        messageID: MessagingMessageID,
        before cursor: MessagingCursor?,
        pageSize: Int
    ) throws -> MessagingPage<MessagingMessageSnapshot> {
        try Self.validate(pageSize: pageSize)
        let scope = MessagingCursor.replyScope(messageID: messageID)
        if let cursor = cursor {
            try MessagingCursorCodec.validate(cursor, expectedScope: scope)
        }
        return try databaseQueue.read { db in
            let rows: [Row]
            if let cursor = cursor {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT payload FROM messaging_message_cache
                        WHERE reply_to_id = ?
                          AND (sort_date < ? OR (sort_date = ? AND sort_id < ?))
                        ORDER BY sort_date DESC, sort_id DESC
                        LIMIT ?
                        """,
                    arguments: [
                        messageID,
                        cursor.sortDate.timeIntervalSince1970,
                        cursor.sortDate.timeIntervalSince1970,
                        cursor.stableID,
                        pageSize + 1
                    ]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT payload FROM messaging_message_cache
                        WHERE reply_to_id = ?
                        ORDER BY sort_date DESC, sort_id DESC
                        LIMIT ?
                        """,
                    arguments: [messageID, pageSize + 1]
                )
            }
            let values: [MessagingMessageSnapshot] = try rows.map {
                try Self.decode(MessagingMessageSnapshot.self, from: $0["payload"])
            }
            return try MessagingPageBuilder.replies(
                values,
                messageID: messageID,
                pageSize: pageSize
            )
        }
    }

    public func cachedPinnedMessages(
        conversationID: MessagingConversationID
    ) throws -> [MessagingMessageSnapshot] {
        try databaseQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT payload FROM messaging_message_cache
                    WHERE conversation_id = ? AND is_pinned = 1
                    ORDER BY sort_date DESC, sort_id DESC
                    """,
                arguments: [conversationID]
            )
            return try rows.map {
                try Self.decode(MessagingMessageSnapshot.self, from: $0["payload"])
            }
        }
    }

    public func cachedMessage(clientMessageID: String) throws -> MessagingMessageSnapshot? {
        try databaseQueue.read { db in
            try Self.fetchMessage(clientMessageID: clientMessageID, in: db)
        }
    }

    public func cachedMessage(objectID: MessagingMessageID) throws -> MessagingMessageSnapshot? {
        try databaseQueue.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT payload FROM messaging_message_cache WHERE object_id = ?",
                arguments: [objectID]
            ) else { return nil }
            return try Self.decode(MessagingMessageSnapshot.self, from: data)
        }
    }

    public func upsert(members: [MessagingMemberSnapshot]) throws {
        guard !members.isEmpty else { return }
        try databaseQueue.write { db in
            for member in members {
                try db.execute(
                    sql: """
                        INSERT INTO messaging_member_cache
                            (object_id, conversation_id, user_id, typing_expires_at, payload)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(object_id) DO UPDATE SET
                            conversation_id = excluded.conversation_id,
                            user_id = excluded.user_id,
                            typing_expires_at = excluded.typing_expires_at,
                            payload = excluded.payload
                        """,
                    arguments: [
                        member.objectID,
                        member.conversationID,
                        member.userID,
                        member.typingExpiresAt?.timeIntervalSince1970,
                        try Self.encode(member)
                    ]
                )
            }
        }
    }

    public func cachedMembers(
        conversationID: MessagingConversationID
    ) throws -> [MessagingMemberSnapshot] {
        try databaseQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT payload FROM messaging_member_cache
                    WHERE conversation_id = ?
                    ORDER BY user_id ASC
                    """,
                arguments: [conversationID]
            )
            return try rows.map {
                try Self.decode(MessagingMemberSnapshot.self, from: $0["payload"])
            }
        }
    }

    public func removeConversation(id: MessagingConversationID) throws {
        try databaseQueue.write { db in
            try purgeConversation(id: id, in: db)
        }
    }

    public func removeAllMessagingData() throws {
        try databaseQueue.write { db in
            try db.execute(sql: "DELETE FROM messaging_attachment_upload")
            try db.execute(sql: "DELETE FROM messaging_outbox")
            try db.execute(sql: "DELETE FROM messaging_member_cache")
            try db.execute(sql: "DELETE FROM messaging_message_cache")
            try db.execute(sql: "DELETE FROM messaging_conversation_cache")
        }
    }

    // MARK: MessagingOutbox

    public func stageSend(
        draft: MessagingMessageDraft,
        authorID: MessagingUserID
    ) throws -> (message: MessagingMessageSnapshot, entry: MessagingOutboxEntry) {
        guard !draft.conversationID.isEmpty, !draft.clientMessageID.isEmpty, !authorID.isEmpty else {
            throw MessagingModelError.invalidDraft("Conversation, client-message, and author IDs are required")
        }
        guard !draft.content.isEmpty || !draft.expressions.isEmpty else {
            throw MessagingModelError.invalidDraft(
                "A message must contain text, media, a link, attributes, or an expression"
            )
        }

        return try databaseQueue.write { db in
            let existingMessage = try Self.fetchMessage(
                clientMessageID: draft.clientMessageID,
                in: db
            )
            let existingEntry = try Self.fetchOutbox(
                idempotencyKey: draft.clientMessageID,
                in: db
            )
            if let existingMessage = existingMessage, let existingEntry = existingEntry {
                return (existingMessage, existingEntry)
            }

            let message = try Self.roundTrip(existingMessage ?? MessagingMessageSnapshot(
                clientMessageID: draft.clientMessageID,
                conversationID: draft.conversationID,
                authorID: authorID,
                clientCreatedAt: draft.clientCreatedAt,
                content: draft.content,
                replyToMessageID: draft.replyToMessageID,
                deliveryKind: draft.deliveryKind,
                localState: .queued
            ))
            try Self.upsert(message: message, in: db)

            if let existingEntry = existingEntry {
                return (message, existingEntry)
            }
            let sequence = try Self.nextSequence(in: db)
            let entry = try Self.roundTrip(MessagingOutboxEntry(
                idempotencyKey: draft.clientMessageID,
                conversationID: draft.conversationID,
                sequence: sequence,
                mutation: .send(draft: draft, authorID: authorID),
                createdAt: draft.clientCreatedAt
            ))
            try Self.insert(outbox: entry, in: db)
            return (message, entry)
        }
    }

    public func enqueue(_ entry: MessagingOutboxEntry) throws -> MessagingOutboxEntry {
        if case .setTyping = entry.mutation {
            throw MessagingPersistenceError.ephemeralMutationCannotBeEnqueued
        }
        return try databaseQueue.write { db in
            if let existing = try Self.fetchOutbox(
                idempotencyKey: entry.idempotencyKey,
                in: db
            ) {
                return existing
            }
            var stored = entry
            stored.sequence = try Self.nextSequence(in: db)
            stored = try Self.roundTrip(stored)
            try Self.insert(outbox: stored, in: db)
            return stored
        }
    }

    public func readyOutboxEntries(
        at date: Date,
        limit: Int
    ) throws -> [MessagingOutboxEntry] {
        guard limit > 0 else { return [] }
        return try databaseQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT current.payload
                    FROM messaging_outbox AS current
                    WHERE current.state IN (?, ?)
                      AND current.next_attempt_at <= ?
                      AND NOT EXISTS (
                          SELECT 1 FROM messaging_outbox AS earlier
                          WHERE earlier.conversation_id = current.conversation_id
                            AND earlier.sequence < current.sequence
                            AND earlier.state <> ?
                      )
                    ORDER BY current.sequence ASC
                    LIMIT ?
                    """,
                arguments: [
                    MessagingOutboxState.queued.rawValue,
                    MessagingOutboxState.retryScheduled.rawValue,
                    date.timeIntervalSince1970,
                    MessagingOutboxState.blocked.rawValue,
                    limit
                ]
            )
            return try rows.map {
                try Self.decode(MessagingOutboxEntry.self, from: $0["payload"])
            }
        }
    }

    public func updateOutboxEntry(_ entry: MessagingOutboxEntry) throws {
        try databaseQueue.write { db in
            guard try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM messaging_outbox WHERE id = ?)",
                arguments: [entry.id]
            ) == true else {
                throw MessagingPersistenceError.outboxEntryNotFound(entry.id)
            }
            try Self.insert(outbox: entry, in: db)
        }
    }

    public func removeOutboxEntry(id: String) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "DELETE FROM messaging_outbox WHERE id = ?",
                arguments: [id]
            )
        }
    }

    public func outboxEntry(idempotencyKey: String) throws -> MessagingOutboxEntry? {
        try databaseQueue.read { db in
            try Self.fetchOutbox(idempotencyKey: idempotencyKey, in: db)
        }
    }

    public func retryBlockedOutboxEntry(
        idempotencyKey: String,
        at date: Date = Date()
    ) throws -> MessagingOutboxEntry {
        try databaseQueue.write { db in
            guard var entry = try Self.fetchOutbox(
                idempotencyKey: idempotencyKey,
                in: db
            ) else {
                throw MessagingPersistenceError.outboxEntryNotFound(idempotencyKey)
            }
            guard entry.state == .blocked else {
                throw MessagingPersistenceError.outboxEntryIsNotBlocked(idempotencyKey)
            }
            entry.state = .queued
            entry.attemptCount = 0
            entry.nextAttemptAt = date
            entry.lastErrorDescription = nil
            try Self.insert(outbox: entry, in: db)
            try Self.updateOptimisticSend(
                for: entry,
                state: .queued,
                failureDescription: nil,
                in: db
            )
            return entry
        }
    }

    public func cancelBlockedOutboxEntry(idempotencyKey: String) throws {
        try databaseQueue.write { db in
            guard let entry = try Self.fetchOutbox(
                idempotencyKey: idempotencyKey,
                in: db
            ) else {
                throw MessagingPersistenceError.outboxEntryNotFound(idempotencyKey)
            }
            guard entry.state == .blocked else {
                throw MessagingPersistenceError.outboxEntryIsNotBlocked(idempotencyKey)
            }
            try db.execute(
                sql: "DELETE FROM messaging_outbox WHERE id = ?",
                arguments: [entry.id]
            )
            if case .send(let draft, _) = entry.mutation {
                try db.execute(
                    sql: "DELETE FROM messaging_attachment_upload WHERE client_message_id = ?",
                    arguments: [draft.clientMessageID]
                )
            }
        }
    }

    public func confirm(
        message: MessagingMessageSnapshot,
        idempotencyKey: String
    ) throws {
        try databaseQueue.write { db in
            var confirmed = message
            confirmed.localState = .confirmed
            confirmed.lastFailureDescription = nil
            try Self.upsert(message: confirmed, in: db)
            try db.execute(
                sql: "DELETE FROM messaging_outbox WHERE idempotency_key = ?",
                arguments: [idempotencyKey]
            )
        }
    }

    // MARK: Database setup

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("messaging-v1") { db in
            try db.create(table: "messaging_conversation_cache") { table in
                table.column("id", .text).primaryKey()
                table.column("sort_date", .double).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.create(
                index: "messaging_conversation_sort",
                on: "messaging_conversation_cache",
                columns: ["sort_date", "id"]
            )

            try db.create(table: "messaging_message_cache") { table in
                table.column("stable_id", .text).primaryKey()
                table.column("object_id", .text).unique(onConflict: .abort)
                table.column("conversation_id", .text).notNull()
                table.column("sort_date", .double).notNull()
                table.column("sort_id", .text).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.create(
                index: "messaging_message_conversation_sort",
                on: "messaging_message_cache",
                columns: ["conversation_id", "sort_date", "sort_id"]
            )

            try db.create(table: "messaging_outbox") { table in
                table.column("id", .text).primaryKey()
                table.column("idempotency_key", .text).notNull().unique(onConflict: .abort)
                table.column("conversation_id", .text).notNull()
                table.column("sequence", .integer).notNull().unique(onConflict: .abort)
                table.column("state", .text).notNull()
                table.column("next_attempt_at", .double).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.create(
                index: "messaging_outbox_ready",
                on: "messaging_outbox",
                columns: ["state", "next_attempt_at", "sequence"]
            )
            try db.create(
                index: "messaging_outbox_conversation_sequence",
                on: "messaging_outbox",
                columns: ["conversation_id", "sequence"]
            )
        }
        migrator.registerMigration("messaging-v2-members-and-uploads") { db in
            try db.create(table: "messaging_member_cache") { table in
                table.column("object_id", .text).primaryKey()
                table.column("conversation_id", .text).notNull()
                table.column("user_id", .text).notNull()
                table.column("typing_expires_at", .double)
                table.column("payload", .blob).notNull()
            }
            try db.create(
                index: "messaging_member_conversation_user",
                on: "messaging_member_cache",
                columns: ["conversation_id", "user_id"],
                unique: true
            )

            try db.create(table: "messaging_attachment_upload") { table in
                table.column("client_message_id", .text).notNull()
                table.column("attachment_key", .text).notNull()
                table.column("payload", .blob).notNull()
                table.primaryKey(["client_message_id", "attachment_key"])
            }
        }
        migrator.registerMigration("messaging-v3-thread-index") { db in
            try db.alter(table: "messaging_message_cache") { table in
                table.add(column: "reply_to_id", .text)
            }
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT stable_id, payload FROM messaging_message_cache"
            )
            for row in rows {
                let message = try Self.decode(
                    MessagingMessageSnapshot.self,
                    from: row["payload"]
                )
                try db.execute(
                    sql: """
                        UPDATE messaging_message_cache
                        SET reply_to_id = ?
                        WHERE stable_id = ?
                        """,
                    arguments: [message.replyToMessageID, row["stable_id"]]
                )
            }
            try db.create(
                index: "messaging_message_reply_sort",
                on: "messaging_message_cache",
                columns: ["reply_to_id", "sort_date", "sort_id"]
            )
        }
        migrator.registerMigration("messaging-v4-pinned-index") { db in
            try db.alter(table: "messaging_message_cache") { table in
                table.add(column: "is_pinned", .boolean).notNull().defaults(to: false)
            }
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT stable_id, payload FROM messaging_message_cache"
            )
            for row in rows {
                let message = try Self.decode(
                    MessagingMessageSnapshot.self,
                    from: row["payload"]
                )
                try db.execute(
                    sql: "UPDATE messaging_message_cache SET is_pinned = ? WHERE stable_id = ?",
                    arguments: [message.isPinned, row["stable_id"]]
                )
            }
            try db.create(
                index: "messaging_message_pinned",
                on: "messaging_message_cache",
                columns: ["conversation_id", "is_pinned", "sort_date", "sort_id"]
            )
        }
        try migrator.migrate(databaseQueue)
    }

    private func recoverInterruptedOperations() throws {
        try databaseQueue.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT payload FROM messaging_outbox WHERE state = ?",
                arguments: [MessagingOutboxState.inFlight.rawValue]
            )
            for row in rows {
                var entry = try Self.decode(
                    MessagingOutboxEntry.self,
                    from: row["payload"]
                )
                entry.state = .retryScheduled
                entry.nextAttemptAt = Date()
                entry.lastErrorDescription = "Recovered after an interrupted attempt"
                try Self.insert(outbox: entry, in: db)
            }
        }
    }

    // MARK: SQL helpers

    private static func upsert(
        conversation: MessagingConversationSnapshot,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO messaging_conversation_cache (id, sort_date, payload)
                VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    sort_date = excluded.sort_date,
                    payload = excluded.payload
                """,
            arguments: [
                conversation.id,
                conversation.lastActivityAt.timeIntervalSince1970,
                try encode(conversation)
            ]
        )
    }

    private static func upsert(
        message: MessagingMessageSnapshot,
        in db: Database
    ) throws {
        if let objectID = message.objectID,
           let conflictingStableID = try String.fetchOne(
               db,
               sql: """
                   SELECT stable_id FROM messaging_message_cache
                   WHERE object_id = ? AND stable_id <> ?
                   """,
               arguments: [objectID, message.stableID]
           ) {
            try db.execute(
                sql: "DELETE FROM messaging_message_cache WHERE stable_id = ?",
                arguments: [conflictingStableID]
            )
        }
        try db.execute(
            sql: """
                INSERT INTO messaging_message_cache
                    (stable_id, object_id, conversation_id, reply_to_id, is_pinned,
                     sort_date, sort_id, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(stable_id) DO UPDATE SET
                    object_id = excluded.object_id,
                    conversation_id = excluded.conversation_id,
                    reply_to_id = excluded.reply_to_id,
                    is_pinned = excluded.is_pinned,
                    sort_date = excluded.sort_date,
                    sort_id = excluded.sort_id,
                    payload = excluded.payload
                """,
            arguments: [
                message.stableID,
                message.objectID,
                message.conversationID,
                message.replyToMessageID,
                message.isPinned,
                message.sortDate.timeIntervalSince1970,
                message.objectID ?? message.stableID,
                try encode(message)
            ]
        )
    }

    private static func insert(
        outbox entry: MessagingOutboxEntry,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO messaging_outbox
                    (id, idempotency_key, conversation_id, sequence, state, next_attempt_at, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    idempotency_key = excluded.idempotency_key,
                    conversation_id = excluded.conversation_id,
                    sequence = excluded.sequence,
                    state = excluded.state,
                    next_attempt_at = excluded.next_attempt_at,
                    payload = excluded.payload
                """,
            arguments: [
                entry.id,
                entry.idempotencyKey,
                entry.conversationID,
                entry.sequence,
                entry.state.rawValue,
                entry.nextAttemptAt.timeIntervalSince1970,
                try encode(entry)
            ]
        )
    }

    private static func fetchMessage(
        clientMessageID: String,
        in db: Database
    ) throws -> MessagingMessageSnapshot? {
        guard let data = try Data.fetchOne(
            db,
            sql: "SELECT payload FROM messaging_message_cache WHERE stable_id = ?",
            arguments: [clientMessageID]
        ) else { return nil }
        return try decode(MessagingMessageSnapshot.self, from: data)
    }

    private static func fetchOutbox(
        idempotencyKey: String,
        in db: Database
    ) throws -> MessagingOutboxEntry? {
        guard let data = try Data.fetchOne(
            db,
            sql: "SELECT payload FROM messaging_outbox WHERE idempotency_key = ?",
            arguments: [idempotencyKey]
        ) else { return nil }
        return try decode(MessagingOutboxEntry.self, from: data)
    }

    private static func updateOptimisticSend(
        for entry: MessagingOutboxEntry,
        state: MessagingLocalMessageState,
        failureDescription: String?,
        in db: Database
    ) throws {
        guard case .send(let draft, _) = entry.mutation,
              var message = try fetchMessage(
                clientMessageID: draft.clientMessageID,
                in: db
              ) else { return }
        message.localState = state
        message.lastFailureDescription = failureDescription
        try upsert(message: message, in: db)
    }

    private static func nextSequence(in db: Database) throws -> Int64 {
        try Int64.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(sequence), 0) + 1 FROM messaging_outbox"
        ) ?? 1
    }

    private func pruneMessages(
        conversationID: MessagingConversationID,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                DELETE FROM messaging_message_cache
                WHERE stable_id IN (
                    SELECT stable_id FROM messaging_message_cache
                    WHERE conversation_id = ?
                      AND stable_id NOT IN (SELECT idempotency_key FROM messaging_outbox)
                    ORDER BY sort_date DESC, sort_id DESC
                    LIMIT -1 OFFSET ?
                )
                """,
            arguments: [conversationID, limits.messagesPerConversation]
        )
    }

    private func purgeConversation(
        id: MessagingConversationID,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                DELETE FROM messaging_attachment_upload
                WHERE client_message_id IN (
                    SELECT stable_id FROM messaging_message_cache
                    WHERE conversation_id = ?
                    UNION
                    SELECT idempotency_key FROM messaging_outbox
                    WHERE conversation_id = ?
                )
                """,
            arguments: [id, id]
        )
        try db.execute(
            sql: "DELETE FROM messaging_outbox WHERE conversation_id = ?",
            arguments: [id]
        )
        try db.execute(
            sql: "DELETE FROM messaging_member_cache WHERE conversation_id = ?",
            arguments: [id]
        )
        try db.execute(
            sql: "DELETE FROM messaging_message_cache WHERE conversation_id = ?",
            arguments: [id]
        )
        try db.execute(
            sql: "DELETE FROM messaging_conversation_cache WHERE id = ?",
            arguments: [id]
        )
    }

    private static func validate(pageSize: Int) throws {
        guard (1...ParseMessagingQueryFactory.maximumPageSize).contains(pageSize) else {
            throw MessagingPaginationError.invalidPageSize(pageSize)
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    private static func roundTrip<T: Codable>(_ value: T) throws -> T {
        try decode(T.self, from: encode(value))
    }
}

public enum MessagingPersistenceError: Error, Equatable {
    case applicationSupportDirectoryUnavailable
    case ephemeralMutationCannotBeEnqueued
    case outboxEntryIsNotBlocked(String)
    case outboxEntryNotFound(String)
}

extension GRDBMessagingStore: ParseMessagingAttachmentUploadCaching {
    public func uploadedFile(
        clientMessageID: String,
        attachmentKey: String
    ) throws -> ParseFile? {
        try databaseQueue.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: """
                    SELECT payload FROM messaging_attachment_upload
                    WHERE client_message_id = ? AND attachment_key = ?
                    """,
                arguments: [clientMessageID, attachmentKey]
            ) else { return nil }
            return try JSONDecoder().decode(ParseFile.self, from: data)
        }
    }

    public func storeUploadedFile(
        _ file: ParseFile,
        clientMessageID: String,
        attachmentKey: String
    ) throws {
        let data = try JSONEncoder().encode(file)
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO messaging_attachment_upload
                        (client_message_id, attachment_key, payload)
                    VALUES (?, ?, ?)
                    ON CONFLICT(client_message_id, attachment_key) DO UPDATE SET
                        payload = excluded.payload
                    """,
                arguments: [clientMessageID, attachmentKey, data]
            )
        }
    }

    public func removeUploadedFiles(clientMessageID: String) throws {
        try databaseQueue.write { db in
            try db.execute(
                sql: "DELETE FROM messaging_attachment_upload WHERE client_message_id = ?",
                arguments: [clientMessageID]
            )
        }
    }
}
