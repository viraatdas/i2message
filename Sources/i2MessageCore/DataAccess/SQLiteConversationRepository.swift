import Foundation

public actor SQLiteConversationRepository: ConversationRepository {
    private let store: ReadOnlyMessagesStore
    private let contactResolver: ContactResolving
    private let changeMonitor: MessagesChangeMonitoring

    public init(
        store: ReadOnlyMessagesStore,
        contactResolver: ContactResolving,
        changeMonitor: MessagesChangeMonitoring
    ) {
        self.store = store
        self.contactResolver = contactResolver
        self.changeMonitor = changeMonitor
    }

    public func conversations(page: PageRequest, filter: ConversationFilter) async throws -> Page<Conversation> {
        try Task.checkCancellation()
        let limit = await store.clampedLimit(page.limit)
        let cursor = MessagesPageCursor.decode(page.cursor, expectedKind: .conversation)
        let records = try await fetchConversationRecords(limit: limit + 1, cursor: cursor, direction: page.direction, filter: filter)
        let hasMore = records.count > limit
        let pageRecords = Array(records.prefix(limit))
        let conversations = try await mapConversations(pageRecords)

        return Page(
            items: conversations,
            nextCursor: pageRecords.last.map { MessagesPageCursor(kind: .conversation, sortValue: $0.sortDateRaw, rowID: $0.rowID).encode() },
            previousCursor: pageRecords.first.map { MessagesPageCursor(kind: .conversation, sortValue: $0.sortDateRaw, rowID: $0.rowID).encode() },
            hasMore: hasMore,
            totalCount: nil
        )
    }

    public func conversation(id: ConversationID) async throws -> Conversation {
        guard let rowID = MessagesIdentifier.rowID(from: id) else {
            throw I2MessageError.notFound(resource: "Conversation", id: id.rawValue)
        }

        let records = try await fetchConversationRecords(
            limit: 2,
            cursor: nil,
            direction: .older,
            filter: ConversationFilter(),
            explicitRowID: rowID
        )

        guard let record = records.first else {
            throw I2MessageError.notFound(resource: "Conversation", id: id.rawValue)
        }

        let conversations = try await mapConversations([record])
        guard let conversation = conversations.first else {
            throw I2MessageError.notFound(resource: "Conversation", id: id.rawValue)
        }

        return conversation
    }

    public nonisolated func observeConversations(filter: ConversationFilter) -> AsyncThrowingStream<[Conversation], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let initialPage = try await self.conversations(page: PageRequest(limit: 80), filter: filter)
                    continuation.yield(initialPage.items)

                    for try await _ in changeMonitor.changes() {
                        try Task.checkCancellation()
                        let page = try await self.conversations(page: PageRequest(limit: 80), filter: filter)
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

    private func fetchConversationRecords(
        limit: Int,
        cursor: MessagesPageCursor?,
        direction: PageDirection,
        filter: ConversationFilter,
        explicitRowID: Int64? = nil
    ) async throws -> [ConversationRecord] {
        try await store.read { connection, schema in
            let query = Self.conversationSQL(
                schema: schema,
                direction: direction,
                filter: filter,
                hasCursor: cursor != nil,
                explicitRowID: explicitRowID
            )

            var bindings = query.bindings
            if let cursor {
                bindings.append(.int64(cursor.sortValue))
                bindings.append(.int64(cursor.sortValue))
                bindings.append(.int64(cursor.rowID))
            }
            bindings.append(.int(limit))

            return try connection.query(query.sql, bindings).map(ConversationRecord.init(row:))
        }
    }

    private func mapConversations(_ records: [ConversationRecord]) async throws -> [Conversation] {
        guard !records.isEmpty else {
            return []
        }

        let participantsByChatID = try await participantContacts(for: records)
        var latestSenderContacts: [MessageHandle: Contact] = [:]
        let senderHandles = records.compactMap(\.latestSenderHandle)

        if !senderHandles.isEmpty {
            latestSenderContacts = try await contactResolver.contacts(for: senderHandles)
        }

        return records.map { record in
            let participants = participantsByChatID[record.rowID] ?? []
            let title = Self.title(for: record, participants: participants)
            let senderID = record.latestSenderHandle.flatMap { latestSenderContacts[$0]?.id }

            return Conversation(
                id: MessagesIdentifier.conversationID(rowID: record.rowID),
                title: title,
                participants: participants,
                kind: MessagesMapping.conversationKind(style: record.style, participantCount: participants.count),
                service: MessagesMapping.service(from: record.serviceName ?? record.latestMessageService),
                unreadCount: max(0, record.unreadCount),
                pinnedRank: record.pinnedRank,
                isMuted: record.isMuted,
                isArchived: record.isArchived,
                lastMessage: record.latestMessageRowID.map { messageRowID in
                    LastMessagePreview(
                        messageID: MessagesIdentifier.messageID(rowID: messageRowID),
                        senderID: senderID,
                        text: record.latestText?.isEmpty == false ? record.latestText! : (record.latestHasAttachments ? "Attachment" : ""),
                        sentAt: MessagesDateConverter.stableDate(from: record.latestDateRaw, fallbackRowID: messageRowID),
                        hasAttachments: record.latestHasAttachments
                    )
                },
                updatedAt: MessagesDateConverter.stableDate(from: record.sortDateRaw, fallbackRowID: record.rowID),
                lastReadMessageID: nil
            )
        }
    }

    private func participantContacts(for records: [ConversationRecord]) async throws -> [Int64: [Contact]] {
        let handlesByChatID = try await fetchParticipantHandles(chatRowIDs: records.map(\.rowID))
        let uniqueHandles = Array(Set(handlesByChatID.values.flatMap { $0 }))
        let contactsByHandle = try await contactResolver.contacts(for: uniqueHandles)

        var participantsByChatID: [Int64: [Contact]] = [:]
        for record in records {
            let handles = handlesByChatID[record.rowID] ?? record.fallbackParticipantHandles
            participantsByChatID[record.rowID] = handles.compactMap { contactsByHandle[$0] }
        }

        return participantsByChatID
    }

    private func fetchParticipantHandles(chatRowIDs: [Int64]) async throws -> [Int64: [MessageHandle]] {
        guard !chatRowIDs.isEmpty else {
            return [:]
        }

        return try await store.read { connection, schema in
            guard schema.hasTable("chat_handle_join") else {
                return [:]
            }

            let handleValue = schema.column("id", in: "handle", qualifiedBy: "h")
            let handleService = schema.column("service", in: "handle", qualifiedBy: "h")
            let placeholders = Array(repeating: "?", count: chatRowIDs.count).joined(separator: ", ")

            let rows = try connection.query(
                """
                SELECT
                    chj.chat_id AS chat_rowid,
                    h.ROWID AS handle_rowid,
                    \(handleValue.sql) AS handle_value,
                    \(handleService.sql) AS handle_service
                FROM chat_handle_join chj
                JOIN handle h ON h.ROWID = chj.handle_id
                WHERE chj.chat_id IN (\(placeholders))
                ORDER BY chj.chat_id ASC, h.ROWID ASC
                """,
                chatRowIDs.map(SQLiteBindValue.int64)
            )

            var handlesByChatID: [Int64: [MessageHandle]] = [:]
            for row in rows {
                guard let chatRowID = row["chat_rowid"].int64,
                      let value = row["handle_value"].string,
                      !value.isEmpty
                else {
                    continue
                }

                let handle = MessageHandle(
                    rowID: row["handle_rowid"].int64,
                    value: value,
                    service: MessagesMapping.service(from: row["handle_service"].string)
                )
                handlesByChatID[chatRowID, default: []].append(handle)
            }

            return handlesByChatID
        }
    }

    private static func title(for record: ConversationRecord, participants: [Contact]) -> String {
        if let displayName = record.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            return displayName
        }

        if participants.count > 1 {
            return participants.prefix(3).map(\.displayName).joined(separator: ", ")
        }

        if let participant = participants.first {
            return participant.displayName
        }

        if let identifier = record.chatIdentifier, !identifier.isEmpty {
            return identifier
        }

        return "Conversation"
    }

    private static func conversationSQL(
        schema: MessagesDatabaseSchema,
        direction: PageDirection,
        filter: ConversationFilter,
        hasCursor: Bool,
        explicitRowID: Int64?
    ) -> (sql: String, bindings: [SQLiteBindValue]) {
        let displayName = schema.column("display_name", in: "chat", qualifiedBy: "c")
        let chatIdentifier = schema.column("chat_identifier", in: "chat", qualifiedBy: "c")
        let chatGuid = schema.column("guid", in: "chat", qualifiedBy: "c")
        let serviceName = schema.coalescedColumns(["service_name", "service"], in: "chat", qualifiedBy: "c")
        let style = schema.column("style", in: "chat", qualifiedBy: "c")
        let archived = schema.coalescedColumns(["is_archived", "is_filtered"], in: "chat", qualifiedBy: "c", fallback: .int(0))
        let muted = schema.coalescedColumns(["is_muted", "is_silenced"], in: "chat", qualifiedBy: "c", fallback: .int(0))
        let pinned = schema.coalescedColumns(["is_pinned", "pinned"], in: "chat", qualifiedBy: "c", fallback: .int(0))
        let latestMessageIDSubquery = latestMessageSubquery(schema: schema, selectedExpression: "m2.ROWID")
        let latestSortDateSubquery = latestMessageSubquery(schema: schema, selectedExpression: latestMessageSortExpression(schema: schema, messageAlias: "m2", joinAlias: "cmj2"))
        let unreadSubquery = unreadCountSubquery(schema: schema)
        let latestText = schema.column("text", in: "message", qualifiedBy: "m")
        let latestDate = schema.column("date", in: "message", qualifiedBy: "m")
        let latestHandleID = schema.column("handle_id", in: "message", qualifiedBy: "m")
        let latestIsFromMe = schema.column("is_from_me", in: "message", qualifiedBy: "m", fallback: .int(0))
        let latestHasAttachments = schema.column("cache_has_attachments", in: "message", qualifiedBy: "m", fallback: .int(0))
        let latestService = schema.column("service", in: "message", qualifiedBy: "m")
        let latestHandleValue = schema.column("id", in: "handle", qualifiedBy: "lh")
        let latestHandleService = schema.column("service", in: "handle", qualifiedBy: "lh")

        var whereClauses: [String] = []
        var bindings: [SQLiteBindValue] = []

        if let explicitRowID {
            whereClauses.append("c.ROWID = ?")
            bindings.append(.int64(explicitRowID))
        }

        if !filter.includeArchived {
            whereClauses.append("COALESCE(\(archived.sql), 0) = 0")
        }

        if filter.unreadOnly {
            whereClauses.append("(\(unreadSubquery)) > 0")
        }

        if filter.pinnedOnly {
            whereClauses.append("COALESCE(\(pinned.sql), 0) != 0")
        }

        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            let likeQuery = "%\(query)%"
            var queryClauses = [
                "LOWER(COALESCE(\(displayName.sql), '')) LIKE ?",
                "LOWER(COALESCE(\(chatIdentifier.sql), '')) LIKE ?"
            ]
            bindings.append(.text(likeQuery))
            bindings.append(.text(likeQuery))

            if schema.hasTable("chat_handle_join") {
                queryClauses.append(
                    """
                    EXISTS (
                        SELECT 1
                        FROM chat_handle_join qchj
                        JOIN handle qh ON qh.ROWID = qchj.handle_id
                        WHERE qchj.chat_id = c.ROWID
                          AND LOWER(COALESCE(qh.id, '')) LIKE ?
                    )
                    """
                )
                bindings.append(.text(likeQuery))
            }

            whereClauses.append("(\(queryClauses.joined(separator: " OR ")))")
        }

        let baseWhere = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"
        let cursorWhere: String
        if hasCursor {
            switch direction {
            case .older:
                cursorWhere = "WHERE (base.latest_sort_date < ? OR (base.latest_sort_date = ? AND base.chat_rowid < ?))"
            case .newer:
                cursorWhere = "WHERE (base.latest_sort_date > ? OR (base.latest_sort_date = ? AND base.chat_rowid > ?))"
            }
        } else {
            cursorWhere = ""
        }

        let sortDirection = direction == .newer ? "ASC" : "DESC"

        let sql = """
        WITH conversation_base AS (
            SELECT
                c.ROWID AS chat_rowid,
                \(chatGuid.sql) AS chat_guid,
                \(chatIdentifier.sql) AS chat_identifier,
                \(displayName.sql) AS display_name,
                \(serviceName.sql) AS service_name,
                \(style.sql) AS style,
                COALESCE(\(archived.sql), 0) AS is_archived,
                COALESCE(\(muted.sql), 0) AS is_muted,
                CASE WHEN COALESCE(\(pinned.sql), 0) != 0 THEN 0 ELSE NULL END AS pinned_rank,
                (\(latestMessageIDSubquery)) AS latest_message_id,
                COALESCE((\(latestSortDateSubquery)), c.ROWID) AS latest_sort_date,
                (\(unreadSubquery)) AS unread_count
            FROM chat c
            \(baseWhere)
        )
        SELECT
            base.*,
            \(latestText.sql) AS latest_text,
            \(latestDate.sql) AS latest_date,
            \(latestHandleID.sql) AS latest_handle_id,
            \(latestIsFromMe.sql) AS latest_is_from_me,
            \(latestHasAttachments.sql) AS latest_has_attachments,
            \(latestService.sql) AS latest_service,
            \(latestHandleValue.sql) AS latest_handle_value,
            \(latestHandleService.sql) AS latest_handle_service
        FROM conversation_base base
        LEFT JOIN message m ON m.ROWID = base.latest_message_id
        LEFT JOIN handle lh ON lh.ROWID = \(latestHandleID.sql)
        \(cursorWhere)
        ORDER BY base.latest_sort_date \(sortDirection), base.chat_rowid \(sortDirection)
        LIMIT ?
        """

        return (sql, bindings)
    }

    private static func latestMessageSubquery(schema: MessagesDatabaseSchema, selectedExpression: String) -> String {
        """
        SELECT \(selectedExpression)
        FROM chat_message_join cmj2
        JOIN message m2 ON m2.ROWID = cmj2.message_id
        WHERE cmj2.chat_id = c.ROWID
          AND \(nonReactionMessageClause(schema: schema, messageAlias: "m2"))
        ORDER BY \(latestMessageSortExpression(schema: schema, messageAlias: "m2", joinAlias: "cmj2")) DESC, m2.ROWID DESC
        LIMIT 1
        """
    }

    private static func latestMessageSortExpression(schema: MessagesDatabaseSchema, messageAlias: String, joinAlias: String) -> String {
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

    private static func unreadCountSubquery(schema: MessagesDatabaseSchema) -> String {
        let isFromMe = schema.column("is_from_me", in: "message", qualifiedBy: "mu", fallback: .int(0))
        let isRead = schema.column("is_read", in: "message", qualifiedBy: "mu", fallback: .int(1))

        return """
        SELECT COUNT(1)
        FROM chat_message_join cmju
        JOIN message mu ON mu.ROWID = cmju.message_id
        WHERE cmju.chat_id = c.ROWID
          AND COALESCE(\(isFromMe.sql), 0) = 0
          AND COALESCE(\(isRead.sql), 1) = 0
        """
    }
}

private struct ConversationRecord: Sendable {
    var rowID: Int64
    var guid: String?
    var chatIdentifier: String?
    var displayName: String?
    var serviceName: String?
    var style: Int?
    var isArchived: Bool
    var isMuted: Bool
    var pinnedRank: Int?
    var latestMessageRowID: Int64?
    var latestText: String?
    var latestDateRaw: Int64?
    var latestHandleRowID: Int64?
    var latestHandleValue: String?
    var latestHandleService: String?
    var latestIsFromMe: Bool
    var latestHasAttachments: Bool
    var latestMessageService: String?
    var sortDateRaw: Int64
    var unreadCount: Int

    init(row: SQLiteRow) {
        rowID = row["chat_rowid"].int64 ?? 0
        guid = row["chat_guid"].string
        chatIdentifier = row["chat_identifier"].string
        displayName = row["display_name"].string
        serviceName = row["service_name"].string
        style = row["style"].int
        isArchived = row["is_archived"].bool ?? false
        isMuted = row["is_muted"].bool ?? false
        pinnedRank = row["pinned_rank"].int
        latestMessageRowID = row["latest_message_id"].int64
        latestText = row["latest_text"].string
        latestDateRaw = row["latest_date"].int64
        latestHandleRowID = row["latest_handle_id"].int64
        latestHandleValue = row["latest_handle_value"].string
        latestHandleService = row["latest_handle_service"].string
        latestIsFromMe = row["latest_is_from_me"].bool ?? false
        latestHasAttachments = row["latest_has_attachments"].bool ?? false
        latestMessageService = row["latest_service"].string
        sortDateRaw = row["latest_sort_date"].int64 ?? rowID
        unreadCount = row["unread_count"].int ?? 0
    }

    var latestSenderHandle: MessageHandle? {
        guard latestIsFromMe == false,
              let latestHandleValue,
              !latestHandleValue.isEmpty
        else {
            return nil
        }

        return MessageHandle(
            rowID: latestHandleRowID,
            value: latestHandleValue,
            service: MessagesMapping.service(from: latestHandleService ?? latestMessageService)
        )
    }

    var fallbackParticipantHandles: [MessageHandle] {
        guard let chatIdentifier, !chatIdentifier.isEmpty else {
            return []
        }

        return [
            MessageHandle(
                rowID: nil,
                value: chatIdentifier,
                service: MessagesMapping.service(from: serviceName)
            )
        ]
    }
}
