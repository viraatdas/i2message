import Foundation

public actor SQLiteMessageRepository: MessageRepository {
    private let store: ReadOnlyMessagesStore
    private let contactResolver: ContactResolving
    private let attachmentRepository: SQLiteAttachmentRepository
    private let changeMonitor: MessagesChangeMonitoring
    private let currentUserID = ContactID(rawValue: "current-user")

    public init(
        store: ReadOnlyMessagesStore,
        contactResolver: ContactResolving,
        attachmentRepository: SQLiteAttachmentRepository,
        changeMonitor: MessagesChangeMonitoring
    ) {
        self.store = store
        self.contactResolver = contactResolver
        self.attachmentRepository = attachmentRepository
        self.changeMonitor = changeMonitor
    }

    public func messages(
        in conversationID: ConversationID,
        page: PageRequest,
        around anchor: MessageID?
    ) async throws -> Page<Message> {
        try Task.checkCancellation()

        guard let conversationRowID = MessagesIdentifier.rowID(from: conversationID) else {
            throw I2MessageError.notFound(resource: "Conversation", id: conversationID.rawValue)
        }

        let limit = await store.clampedLimit(page.limit)
        let records: [MessageRecord]
        let hasMore: Bool

        if let anchor {
            records = try await fetchMessageRecordsAround(anchor: anchor, conversationRowID: conversationRowID, limit: limit)
            hasMore = records.count >= limit
        } else {
            let cursor = MessagesPageCursor.decode(page.cursor, expectedKind: .message)
            let fetched = try await fetchMessageRecords(
                conversationRowID: conversationRowID,
                limit: limit + 1,
                cursor: cursor,
                direction: page.direction
            )
            hasMore = fetched.count > limit
            records = Array(fetched.prefix(limit))
        }

        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.sortDateRaw == rhs.sortDateRaw {
                return lhs.rowID > rhs.rowID
            }
            return lhs.sortDateRaw > rhs.sortDateRaw
        }
        let messages = try await mapMessages(sortedRecords, conversationID: conversationID)

        return Page(
            items: messages,
            nextCursor: sortedRecords.last.map { MessagesPageCursor(kind: .message, sortValue: $0.sortDateRaw, rowID: $0.rowID).encode() },
            previousCursor: sortedRecords.first.map { MessagesPageCursor(kind: .message, sortValue: $0.sortDateRaw, rowID: $0.rowID).encode() },
            hasMore: hasMore,
            totalCount: nil
        )
    }

    public func message(id: MessageID) async throws -> Message {
        guard let messageRowID = MessagesIdentifier.rowID(from: id) else {
            throw I2MessageError.notFound(resource: "Message", id: id.rawValue)
        }

        let record = try await fetchMessageRecord(rowID: messageRowID)
        let conversationID = MessagesIdentifier.conversationID(rowID: record.chatRowID)
        let messages = try await mapMessages([record], conversationID: conversationID)

        guard let message = messages.first else {
            throw I2MessageError.notFound(resource: "Message", id: id.rawValue)
        }

        return message
    }

    public nonisolated func observeMessages(in conversationID: ConversationID) -> AsyncThrowingStream<[Message], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let initialPage = try await self.messages(in: conversationID, page: PageRequest(limit: 80), around: nil)
                    continuation.yield(initialPage.items)

                    for try await _ in changeMonitor.changes() {
                        try Task.checkCancellation()
                        let page = try await self.messages(in: conversationID, page: PageRequest(limit: 80), around: nil)
                        continuation.yield(page.items)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func fetchMessageRecord(rowID: Int64) async throws -> MessageRecord {
        let records = try await store.read { connection, schema in
            let sql = Self.messageSelectSQL(schema: schema, whereClause: "m.ROWID = ?", orderClause: "m.ROWID DESC", limitClause: "LIMIT 1")
            return try connection.query(sql, [.int64(rowID)]).map(MessageRecord.init(row:))
        }

        guard let record = records.first else {
            throw I2MessageError.notFound(resource: "Message", id: "message:\(rowID)")
        }

        return record
    }

    private func fetchMessageRecords(
        conversationRowID: Int64,
        limit: Int,
        cursor: MessagesPageCursor?,
        direction: PageDirection
    ) async throws -> [MessageRecord] {
        try await store.read { connection, schema in
            let sortExpression = Self.messageSortExpression(schema: schema, messageAlias: "m", joinAlias: "cmj")
            var whereClauses = ["cmj.chat_id = ?"]
            var bindings: [SQLiteBindValue] = [.int64(conversationRowID)]

            whereClauses.append(Self.nonReactionMessageClause(schema: schema, messageAlias: "m"))

            if let cursor {
                switch direction {
                case .older:
                    whereClauses.append("(\(sortExpression) < ? OR (\(sortExpression) = ? AND m.ROWID < ?))")
                case .newer:
                    whereClauses.append("(\(sortExpression) > ? OR (\(sortExpression) = ? AND m.ROWID > ?))")
                }
                bindings.append(.int64(cursor.sortValue))
                bindings.append(.int64(cursor.sortValue))
                bindings.append(.int64(cursor.rowID))
            }

            bindings.append(.int(limit))
            let orderDirection = direction == .newer ? "ASC" : "DESC"
            let sql = Self.messageSelectSQL(
                schema: schema,
                whereClause: whereClauses.joined(separator: " AND "),
                orderClause: "\(sortExpression) \(orderDirection), m.ROWID \(orderDirection)",
                limitClause: "LIMIT ?"
            )

            return try connection.query(sql, bindings).map(MessageRecord.init(row:))
        }
    }

    private func fetchMessageRecordsAround(anchor: MessageID, conversationRowID: Int64, limit: Int) async throws -> [MessageRecord] {
        guard let anchorRowID = MessagesIdentifier.rowID(from: anchor) else {
            throw I2MessageError.notFound(resource: "Message", id: anchor.rawValue)
        }

        let anchorRecord = try await fetchMessageRecord(rowID: anchorRowID)
        guard anchorRecord.chatRowID == conversationRowID else {
            throw I2MessageError.notFound(resource: "Message", id: anchor.rawValue)
        }

        let newerLimit = max(0, limit / 2)
        let olderLimit = max(1, limit - newerLimit)

        return try await store.read { connection, schema in
            let sortExpression = Self.messageSortExpression(schema: schema, messageAlias: "m", joinAlias: "cmj")
            let baseWhere = "cmj.chat_id = ? AND \(Self.nonReactionMessageClause(schema: schema, messageAlias: "m"))"
            let newerSQL = Self.messageSelectSQL(
                schema: schema,
                whereClause: "\(baseWhere) AND (\(sortExpression) > ? OR (\(sortExpression) = ? AND m.ROWID > ?))",
                orderClause: "\(sortExpression) ASC, m.ROWID ASC",
                limitClause: "LIMIT ?"
            )
            let olderSQL = Self.messageSelectSQL(
                schema: schema,
                whereClause: "\(baseWhere) AND (\(sortExpression) < ? OR (\(sortExpression) = ? AND m.ROWID <= ?))",
                orderClause: "\(sortExpression) DESC, m.ROWID DESC",
                limitClause: "LIMIT ?"
            )

            let newerRows = newerLimit == 0 ? [] : try connection.query(
                newerSQL,
                [
                    .int64(conversationRowID),
                    .int64(anchorRecord.sortDateRaw),
                    .int64(anchorRecord.sortDateRaw),
                    .int64(anchorRecord.rowID),
                    .int(newerLimit)
                ]
            ).map(MessageRecord.init(row:))

            let olderRows = try connection.query(
                olderSQL,
                [
                    .int64(conversationRowID),
                    .int64(anchorRecord.sortDateRaw),
                    .int64(anchorRecord.sortDateRaw),
                    .int64(anchorRecord.rowID),
                    .int(olderLimit)
                ]
            ).map(MessageRecord.init(row:))

            return newerRows + olderRows
        }
    }

    private func mapMessages(_ records: [MessageRecord], conversationID: ConversationID) async throws -> [Message] {
        guard !records.isEmpty else {
            return []
        }

        let senderHandles = records.compactMap(\.senderHandle)
        let contactsByHandle = try await contactResolver.contacts(for: Array(Set(senderHandles)))
        let attachmentsByMessageID = try await attachmentRepository.attachments(forMessageRowIDs: records.map(\.rowID))
        let reactionsByGUID = try await fetchReactions(targetGUIDs: records.compactMap(\.guid))

        return records.map { record in
            let senderID = record.isFromMe ? nil : record.senderHandle.flatMap { contactsByHandle[$0]?.id }
            let body: MessageBody = record.text?.isEmpty == false ? .text(record.text!) : .empty

            return Message(
                id: MessagesIdentifier.messageID(rowID: record.rowID),
                conversationID: conversationID,
                senderID: senderID,
                body: body,
                direction: MessagesMapping.direction(isFromMe: record.isFromMe, itemType: record.itemType),
                service: MessagesMapping.service(from: record.service),
                status: MessagesMapping.deliveryStatus(
                    isFromMe: record.isFromMe,
                    isRead: record.isRead,
                    dateReadRaw: record.dateReadRaw,
                    dateDeliveredRaw: record.dateDeliveredRaw,
                    errorCode: record.errorCode
                ),
                sentAt: MessagesDateConverter.stableDate(from: record.dateRaw, fallbackRowID: record.rowID),
                receivedAt: record.dateReceivedRaw.flatMap(MessagesDateConverter.date(from:)),
                attachments: attachmentsByMessageID[record.rowID] ?? [],
                reactions: record.guid.flatMap { reactionsByGUID[$0] } ?? [],
                replyToMessageID: record.replyToRowID.map(MessagesIdentifier.messageID(rowID:)),
                isEdited: (record.dateEditedRaw ?? 0) > 0,
                isDeleted: (record.dateRetractedRaw ?? 0) > 0
            )
        }
    }

    private func fetchReactions(targetGUIDs: [String]) async throws -> [String: [MessageReaction]] {
        guard !targetGUIDs.isEmpty else {
            return [:]
        }

        let reactionRows = try await store.read { connection, schema in
            guard schema.hasColumn("associated_message_guid", in: "message"),
                  schema.hasColumn("associated_message_type", in: "message")
            else {
                return [ReactionRecord]()
            }

            let associatedGUID = schema.column("associated_message_guid", in: "message", qualifiedBy: "r")
            let associatedType = schema.column("associated_message_type", in: "message", qualifiedBy: "r")
            let text = schema.column("text", in: "message", qualifiedBy: "r")
            let date = schema.column("date", in: "message", qualifiedBy: "r")
            let handleID = schema.column("handle_id", in: "message", qualifiedBy: "r")
            let isFromMe = schema.column("is_from_me", in: "message", qualifiedBy: "r", fallback: .int(0))
            let handleValue = schema.column("id", in: "handle", qualifiedBy: "h")
            let handleService = schema.column("service", in: "handle", qualifiedBy: "h")
            let matchingGUIDs = targetGUIDs + targetGUIDs.map { "p:0/\($0)" }
            let placeholders = Array(repeating: "?", count: matchingGUIDs.count).joined(separator: ", ")

            let rows = try connection.query(
                """
                SELECT
                    r.ROWID AS reaction_rowid,
                    \(associatedGUID.sql) AS target_guid,
                    \(associatedType.sql) AS associated_type,
                    \(text.sql) AS reaction_text,
                    \(date.sql) AS reaction_date,
                    \(handleID.sql) AS handle_rowid,
                    \(isFromMe.sql) AS is_from_me,
                    \(handleValue.sql) AS handle_value,
                    \(handleService.sql) AS handle_service
                FROM message r
                LEFT JOIN handle h ON h.ROWID = \(handleID.sql)
                WHERE \(associatedGUID.sql) IN (\(placeholders))
                  AND \(associatedType.sql) BETWEEN 2000 AND 2999
                ORDER BY \(date.sql) ASC, r.ROWID ASC
                """,
                matchingGUIDs.map(SQLiteBindValue.text)
            )

            return rows.map(ReactionRecord.init(row:))
        }

        let handles = reactionRows.compactMap(\.senderHandle)
        let contactsByHandle = try await contactResolver.contacts(for: Array(Set(handles)))
        var grouped: [String: [MessageReaction]] = [:]

        for row in reactionRows {
            guard let targetGUID = row.normalizedTargetGUID,
                  let kind = MessagesMapping.reactionKind(associatedMessageType: row.associatedType, fallbackText: row.text)
            else {
                continue
            }

            let senderID: ContactID
            if row.isFromMe {
                senderID = currentUserID
            } else if let handle = row.senderHandle, let contact = contactsByHandle[handle] {
                senderID = contact.id
            } else {
                senderID = currentUserID
            }

            grouped[targetGUID, default: []].append(
                MessageReaction(
                    id: "reaction:\(row.rowID)",
                    kind: kind,
                    senderID: senderID,
                    createdAt: MessagesDateConverter.stableDate(from: row.dateRaw, fallbackRowID: row.rowID),
                    displayText: row.text
                )
            )
        }

        return grouped
    }

    private static func messageSelectSQL(
        schema: MessagesDatabaseSchema,
        whereClause: String,
        orderClause: String,
        limitClause: String
    ) -> String {
        let messageGuid = schema.column("guid", in: "message", qualifiedBy: "m")
        let text = schema.column("text", in: "message", qualifiedBy: "m")
        let service = schema.column("service", in: "message", qualifiedBy: "m")
        let date = schema.column("date", in: "message", qualifiedBy: "m")
        let dateRead = schema.column("date_read", in: "message", qualifiedBy: "m")
        let dateDelivered = schema.column("date_delivered", in: "message", qualifiedBy: "m")
        let dateReceived = schema.column("date_played", in: "message", qualifiedBy: "m")
        let dateEdited = schema.column("date_edited", in: "message", qualifiedBy: "m")
        let dateRetracted = schema.column("date_retracted", in: "message", qualifiedBy: "m")
        let handleID = schema.column("handle_id", in: "message", qualifiedBy: "m")
        let isFromMe = schema.column("is_from_me", in: "message", qualifiedBy: "m", fallback: .int(0))
        let isRead = schema.column("is_read", in: "message", qualifiedBy: "m")
        let itemType = schema.column("item_type", in: "message", qualifiedBy: "m")
        let error = schema.column("error", in: "message", qualifiedBy: "m")
        let sortExpression = messageSortExpression(schema: schema, messageAlias: "m", joinAlias: "cmj")
        let threadOriginatorGUID = schema.column("thread_originator_guid", in: "message", qualifiedBy: "m")
        let handleValue = schema.column("id", in: "handle", qualifiedBy: "h")
        let handleService = schema.column("service", in: "handle", qualifiedBy: "h")
        let parentGuid = schema.column("guid", in: "message", qualifiedBy: "parent")

        return """
        SELECT
            cmj.chat_id AS chat_rowid,
            m.ROWID AS message_rowid,
            \(messageGuid.sql) AS message_guid,
            \(text.sql) AS message_text,
            \(service.sql) AS service,
            \(date.sql) AS message_date,
            \(dateRead.sql) AS date_read,
            \(dateDelivered.sql) AS date_delivered,
            \(dateReceived.sql) AS date_received,
            \(dateEdited.sql) AS date_edited,
            \(dateRetracted.sql) AS date_retracted,
            \(handleID.sql) AS handle_rowid,
            \(isFromMe.sql) AS is_from_me,
            \(isRead.sql) AS is_read,
            \(itemType.sql) AS item_type,
            \(error.sql) AS error_code,
            \(sortExpression) AS sort_date,
            \(handleValue.sql) AS handle_value,
            \(handleService.sql) AS handle_service,
            parent.ROWID AS reply_to_rowid,
            \(parentGuid.sql) AS reply_to_guid
        FROM chat_message_join cmj
        JOIN message m ON m.ROWID = cmj.message_id
        LEFT JOIN handle h ON h.ROWID = \(handleID.sql)
        LEFT JOIN message parent ON \(parentGuid.sql) = \(threadOriginatorGUID.sql)
        WHERE \(whereClause)
        ORDER BY \(orderClause)
        \(limitClause)
        """
    }

    private static func messageSortExpression(schema: MessagesDatabaseSchema, messageAlias: String, joinAlias: String) -> String {
        if schema.hasColumn("message_date", in: "chat_message_join"), schema.hasColumn("date", in: "message") {
            return "COALESCE(\(joinAlias).message_date, \(messageAlias).date, \(messageAlias).ROWID)"
        }

        if schema.hasColumn("message_date", in: "chat_message_join") {
            return "COALESCE(\(joinAlias).message_date, \(messageAlias).ROWID)"
        }

        if schema.hasColumn("date", in: "message") {
            return "COALESCE(\(messageAlias).date, \(messageAlias).ROWID)"
        }

        return "\(messageAlias).ROWID"
    }

    private static func nonReactionMessageClause(schema: MessagesDatabaseSchema, messageAlias: String) -> String {
        guard schema.hasColumn("associated_message_type", in: "message") else {
            return "1 = 1"
        }

        return "COALESCE(\(messageAlias).associated_message_type, 0) NOT BETWEEN 2000 AND 2999"
    }
}

private struct MessageRecord: Sendable {
    var chatRowID: Int64
    var rowID: Int64
    var guid: String?
    var text: String?
    var service: String?
    var dateRaw: Int64?
    var dateReadRaw: Int64?
    var dateDeliveredRaw: Int64?
    var dateReceivedRaw: Int64?
    var dateEditedRaw: Int64?
    var dateRetractedRaw: Int64?
    var handleRowID: Int64?
    var handleValue: String?
    var handleService: String?
    var isFromMe: Bool
    var isRead: Bool?
    var itemType: Int?
    var errorCode: Int?
    var sortDateRaw: Int64
    var replyToRowID: Int64?

    init(row: SQLiteRow) {
        chatRowID = row["chat_rowid"].int64 ?? 0
        rowID = row["message_rowid"].int64 ?? 0
        guid = row["message_guid"].string
        text = row["message_text"].string
        service = row["service"].string
        dateRaw = row["message_date"].int64
        dateReadRaw = row["date_read"].int64
        dateDeliveredRaw = row["date_delivered"].int64
        dateReceivedRaw = row["date_received"].int64
        dateEditedRaw = row["date_edited"].int64
        dateRetractedRaw = row["date_retracted"].int64
        handleRowID = row["handle_rowid"].int64
        handleValue = row["handle_value"].string
        handleService = row["handle_service"].string
        isFromMe = row["is_from_me"].bool ?? false
        isRead = row["is_read"].bool
        itemType = row["item_type"].int
        errorCode = row["error_code"].int
        sortDateRaw = row["sort_date"].int64 ?? rowID
        replyToRowID = row["reply_to_rowid"].int64
    }

    var senderHandle: MessageHandle? {
        guard !isFromMe,
              let handleValue,
              !handleValue.isEmpty
        else {
            return nil
        }

        return MessageHandle(
            rowID: handleRowID,
            value: handleValue,
            service: MessagesMapping.service(from: handleService ?? service)
        )
    }
}

private struct ReactionRecord: Sendable {
    var rowID: Int64
    var targetGUID: String?
    var associatedType: Int?
    var text: String?
    var dateRaw: Int64?
    var handleRowID: Int64?
    var handleValue: String?
    var handleService: String?
    var isFromMe: Bool

    init(row: SQLiteRow) {
        rowID = row["reaction_rowid"].int64 ?? 0
        targetGUID = row["target_guid"].string
        associatedType = row["associated_type"].int
        text = row["reaction_text"].string
        dateRaw = row["reaction_date"].int64
        handleRowID = row["handle_rowid"].int64
        handleValue = row["handle_value"].string
        handleService = row["handle_service"].string
        isFromMe = row["is_from_me"].bool ?? false
    }

    var normalizedTargetGUID: String? {
        guard let targetGUID, !targetGUID.isEmpty else {
            return nil
        }

        if let slashIndex = targetGUID.lastIndex(of: "/") {
            return String(targetGUID[targetGUID.index(after: slashIndex)...])
        }

        return targetGUID
    }

    var senderHandle: MessageHandle? {
        guard !isFromMe,
              let handleValue,
              !handleValue.isEmpty
        else {
            return nil
        }

        return MessageHandle(
            rowID: handleRowID,
            value: handleValue,
            service: MessagesMapping.service(from: handleService)
        )
    }
}
