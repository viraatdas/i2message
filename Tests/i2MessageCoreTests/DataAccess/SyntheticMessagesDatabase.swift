import Foundation
import SQLite3
@testable import i2MessageCore

enum SyntheticMessagesDatabase {
    static func makeSmallDatabase() throws -> URL {
        let url = try makeDatabaseURL(name: "small")
        let database = try WritableSQLiteDatabase(url: url)
        try createSchema(database)
        try seedSmall(database)
        return url
    }

    static func makeLargeDatabase(conversationCount: Int = 120, messagesPerConversation: Int = 40) throws -> URL {
        let url = try makeDatabaseURL(name: "large")
        let database = try WritableSQLiteDatabase(url: url)
        try createSchema(database)
        try seedLarge(database, conversationCount: conversationCount, messagesPerConversation: messagesPerConversation)
        return url
    }

    static func makeUnsupportedDatabase() throws -> URL {
        let url = try makeDatabaseURL(name: "unsupported")
        let database = try WritableSQLiteDatabase(url: url)
        try database.execute("CREATE TABLE unrelated (id INTEGER PRIMARY KEY, value TEXT)")
        return url
    }

    private static func makeDatabaseURL(name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("i2message-data-access-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(name).chat.db")
    }

    private static func createSchema(_ database: WritableSQLiteDatabase) throws {
        try database.execute(
            """
            CREATE TABLE chat (
                guid TEXT,
                chat_identifier TEXT,
                display_name TEXT,
                service_name TEXT,
                style INTEGER,
                is_archived INTEGER,
                is_muted INTEGER,
                is_pinned INTEGER
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE handle (
                id TEXT,
                service TEXT,
                uncanonicalized_id TEXT
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE chat_handle_join (
                chat_id INTEGER NOT NULL,
                handle_id INTEGER NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE message (
                guid TEXT,
                text TEXT,
                handle_id INTEGER,
                service TEXT,
                date INTEGER,
                date_read INTEGER,
                date_delivered INTEGER,
                date_played INTEGER,
                date_edited INTEGER,
                date_retracted INTEGER,
                is_from_me INTEGER,
                is_read INTEGER,
                item_type INTEGER,
                "error" INTEGER,
                cache_has_attachments INTEGER,
                associated_message_guid TEXT,
                associated_message_type INTEGER,
                associated_message_emoji TEXT,
                thread_originator_guid TEXT
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE chat_message_join (
                chat_id INTEGER NOT NULL,
                message_id INTEGER NOT NULL,
                message_date INTEGER
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE attachment (
                guid TEXT,
                filename TEXT,
                uti TEXT,
                mime_type TEXT,
                transfer_name TEXT,
                total_bytes INTEGER,
                width INTEGER,
                height INTEGER,
                duration REAL
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE message_attachment_join (
                message_id INTEGER NOT NULL,
                attachment_id INTEGER NOT NULL
            )
            """
        )
        try database.execute("CREATE INDEX idx_chat_message_join_chat_date ON chat_message_join(chat_id, message_date, message_id)")
        try database.execute("CREATE INDEX idx_chat_handle_join_chat ON chat_handle_join(chat_id, handle_id)")
        try database.execute("CREATE INDEX idx_message_associated_guid ON message(associated_message_guid, associated_message_type)")
    }

    private static func seedSmall(_ database: WritableSQLiteDatabase) throws {
        try database.execute("INSERT INTO handle (ROWID, id, service, uncanonicalized_id) VALUES (1, '+1 (555) 123-0001', 'iMessage', '+15551230001')")
        try database.execute("INSERT INTO handle (ROWID, id, service, uncanonicalized_id) VALUES (2, 'bob@example.com', 'iMessage', 'bob@example.com')")
        try database.execute("INSERT INTO chat (ROWID, guid, chat_identifier, display_name, service_name, style, is_archived, is_muted, is_pinned) VALUES (1, 'chat-1', '+15551230001', NULL, 'iMessage', 45, 0, 0, 1)")
        try database.execute("INSERT INTO chat (ROWID, guid, chat_identifier, display_name, service_name, style, is_archived, is_muted, is_pinned) VALUES (2, 'chat-2', 'group-1', 'Launch Team', 'iMessage', 43, 0, 0, 0)")
        try database.execute("INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (1, 1)")
        try database.execute("INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (2, 1)")
        try database.execute("INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (2, 2)")

        try insertMessage(
            database,
            rowID: 1,
            chatID: 1,
            guid: "msg-1",
            text: "Hello from Alice",
            handleID: 1,
            date: 700_000_000_000_000_001,
            isFromMe: false,
            isRead: false,
            hasAttachments: false
        )
        try insertMessage(
            database,
            rowID: 2,
            chatID: 1,
            guid: "msg-2",
            text: "Here is the file",
            handleID: nil,
            date: 700_000_000_000_000_002,
            isFromMe: true,
            isRead: true,
            hasAttachments: true
        )
        try insertMessage(
            database,
            rowID: 3,
            chatID: 2,
            guid: "msg-3",
            text: "Group update",
            handleID: 2,
            date: 700_000_000_000_000_003,
            isFromMe: false,
            isRead: true,
            hasAttachments: false
        )
        try insertMessage(
            database,
            rowID: 4,
            chatID: 1,
            guid: "reaction-1",
            text: nil,
            handleID: 1,
            date: 700_000_000_000_000_004,
            isFromMe: false,
            isRead: true,
            hasAttachments: false,
            associatedGUID: "p:0/msg-2",
            associatedType: 2001
        )

        // Edited message with NO recoverable text or edit chain (attachment-only
        // edit): regression guard for the removeLast-on-empty crash.
        try insertMessage(
            database,
            rowID: 9,
            chatID: 2,
            guid: "msg-9-edited-no-text",
            text: nil,
            handleID: 2,
            date: 700_000_000_000_000_009,
            isFromMe: false,
            isRead: true,
            hasAttachments: false,
            dateEdited: 700_000_000_000_000_010
        )

        // Message with the full tapback lifecycle: a loved tapback addressed via
        // the "bp:" prefix, a custom-emoji tapback, then a removal of the love.
        try insertMessage(
            database,
            rowID: 5,
            chatID: 1,
            guid: "msg-5",
            text: "React to me",
            handleID: nil,
            date: 700_000_000_000_000_005,
            isFromMe: true,
            isRead: true,
            hasAttachments: false,
            dateRead: 700_000_000_000_000_055
        )
        try insertMessage(
            database,
            rowID: 6,
            chatID: 1,
            guid: "reaction-2",
            text: nil,
            handleID: 1,
            date: 700_000_000_000_000_006,
            isFromMe: false,
            isRead: true,
            hasAttachments: false,
            associatedGUID: "bp:msg-5",
            associatedType: 2000
        )
        try insertMessage(
            database,
            rowID: 7,
            chatID: 1,
            guid: "reaction-3",
            text: nil,
            handleID: 1,
            date: 700_000_000_000_000_007,
            isFromMe: false,
            isRead: true,
            hasAttachments: false,
            associatedGUID: "p:0/msg-5",
            associatedType: 2006,
            associatedEmoji: "🫡"
        )
        try insertMessage(
            database,
            rowID: 8,
            chatID: 1,
            guid: "reaction-4",
            text: nil,
            handleID: 1,
            date: 700_000_000_000_000_008,
            isFromMe: false,
            isRead: true,
            hasAttachments: false,
            associatedGUID: "bp:msg-5",
            associatedType: 3000
        )

        try database.execute(
            """
            INSERT INTO attachment (ROWID, guid, filename, uti, mime_type, transfer_name, total_bytes, width, height, duration)
            VALUES (1, 'att-1', '~/Library/Messages/Attachments/demo/photo.png', 'public.png', 'image/png', 'photo.png', 42, 640, 480, NULL)
            """
        )
        try database.execute("INSERT INTO message_attachment_join (message_id, attachment_id) VALUES (2, 1)")
    }

    private static func seedLarge(_ database: WritableSQLiteDatabase, conversationCount: Int, messagesPerConversation: Int) throws {
        var handleRowID = 1
        var messageRowID = 1

        for chatRowID in 1...conversationCount {
            let handleValue = "+1555\(String(format: "%07d", chatRowID))"
            try database.execute("INSERT INTO handle (ROWID, id, service) VALUES (\(handleRowID), '\(handleValue)', 'iMessage')")
            try database.execute("INSERT INTO chat (ROWID, guid, chat_identifier, display_name, service_name, style, is_archived, is_muted, is_pinned) VALUES (\(chatRowID), 'chat-\(chatRowID)', '\(handleValue)', NULL, 'iMessage', 45, 0, 0, 0)")
            try database.execute("INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (\(chatRowID), \(handleRowID))")

            for messageIndex in 1...messagesPerConversation {
                let date = 700_000_000_000_000_000 + Int64(chatRowID * 10_000 + messageIndex)
                try insertMessage(
                    database,
                    rowID: messageRowID,
                    chatID: chatRowID,
                    guid: "msg-\(messageRowID)",
                    text: "Synthetic message \(messageIndex) in chat \(chatRowID)",
                    handleID: messageIndex.isMultiple(of: 2) ? nil : handleRowID,
                    date: date,
                    isFromMe: messageIndex.isMultiple(of: 2),
                    isRead: true,
                    hasAttachments: false
                )
                messageRowID += 1
            }

            handleRowID += 1
        }
    }

    private static func insertMessage(
        _ database: WritableSQLiteDatabase,
        rowID: Int,
        chatID: Int,
        guid: String,
        text: String?,
        handleID: Int?,
        date: Int64,
        isFromMe: Bool,
        isRead: Bool,
        hasAttachments: Bool,
        associatedGUID: String? = nil,
        associatedType: Int? = nil,
        associatedEmoji: String? = nil,
        dateRead: Int64 = 0,
        dateEdited: Int64 = 0
    ) throws {
        try database.execute(
            """
            INSERT INTO message (
                ROWID, guid, text, handle_id, service, date, date_read, date_delivered, date_played,
                date_edited, date_retracted, is_from_me, is_read, item_type, "error",
                cache_has_attachments, associated_message_guid, associated_message_type, associated_message_emoji, thread_originator_guid
            ) VALUES (
                \(rowID),
                \(guid.sqlLiteral),
                \(text.sqlLiteral),
                \(handleID.sqlLiteral),
                'iMessage',
                \(date),
                \(dateRead),
                \(isFromMe ? date + 10 : 0),
                0,
                \(dateEdited),
                0,
                \(isFromMe ? 1 : 0),
                \(isRead ? 1 : 0),
                0,
                0,
                \(hasAttachments ? 1 : 0),
                \(associatedGUID.sqlLiteral),
                \(associatedType.sqlLiteral),
                \(associatedEmoji.sqlLiteral),
                NULL
            )
            """
        )
        try database.execute("INSERT INTO chat_message_join (chat_id, message_id, message_date) VALUES (\(chatID), \(rowID), \(date))")
    }
}

private final class WritableSQLiteDatabase {
    private var database: OpaquePointer?
    private let url: URL

    init(url: URL) throws {
        self.url = url
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK else {
            throw NSError(domain: "SyntheticMessagesDatabase", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Could not open synthetic database at \(url.path)"])
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite fixture statement failed."
            sqlite3_free(errorMessage)
            throw NSError(domain: "SyntheticMessagesDatabase", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "\(message) in \(url.path)"])
        }
    }
}

private extension Optional where Wrapped == String {
    var sqlLiteral: String {
        switch self {
        case .some(let value):
            return value.sqlLiteral
        case .none:
            return "NULL"
        }
    }
}

private extension Optional where Wrapped == Int {
    var sqlLiteral: String {
        switch self {
        case .some(let value):
            return "\(value)"
        case .none:
            return "NULL"
        }
    }
}

private extension String {
    var sqlLiteral: String {
        "'\(replacingOccurrences(of: "'", with: "''"))'"
    }
}
