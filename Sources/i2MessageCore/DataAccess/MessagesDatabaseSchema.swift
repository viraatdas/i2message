import Foundation

struct MessagesDatabaseSchema: Sendable {
    var userVersion: Int
    var tables: Set<String>
    var columnsByTable: [String: Set<String>]

    static func inspect(_ connection: SQLiteConnection) throws -> MessagesDatabaseSchema {
        let tableRows = try connection.query(
            """
            SELECT name
            FROM sqlite_master
            WHERE type = 'table'
            """
        )
        let tables = Set(tableRows.compactMap { $0["name"].string })
        var columnsByTable: [String: Set<String>] = [:]

        for table in tables {
            columnsByTable[table] = try connection.columns(in: table)
        }

        return MessagesDatabaseSchema(
            userVersion: try connection.userVersion(),
            tables: tables,
            columnsByTable: columnsByTable
        )
    }

    func hasTable(_ table: String) -> Bool {
        tables.contains(table)
    }

    func hasColumn(_ column: String, in table: String) -> Bool {
        columnsByTable[table]?.contains(column) == true
    }

    func requiredTableDiagnostics() -> [MessagesStoreDiagnostic] {
        let requiredTables = ["chat", "message", "handle", "chat_message_join"]
        let missing = requiredTables.filter { !hasTable($0) }

        guard !missing.isEmpty else {
            return []
        }

        return [
            MessagesStoreDiagnostic(
                code: .unsupportedSchema,
                severity: .error,
                message: "Messages database schema is missing required tables: \(missing.joined(separator: ", ")).",
                recoverySuggestion: "This chat.db version is not supported yet; no data will be read or modified."
            )
        ]
    }

    func requireReadableMessagesSchema(databasePath: String) throws {
        let diagnostics = requiredTableDiagnostics()
        guard diagnostics.isEmpty else {
            throw I2MessageError.databaseUnavailable(
                path: databasePath,
                reason: diagnostics.first?.message ?? "Unsupported Messages schema."
            )
        }
    }

    func column(_ column: String, in table: String, qualifiedBy alias: String? = nil, fallback: SQLExpression = .null) -> SQLExpression {
        guard hasColumn(column, in: table) else {
            return fallback
        }

        let prefix = alias.map { "\(SQLiteIdentifier.quote($0))." } ?? ""
        return .raw("\(prefix)\(SQLiteIdentifier.quote(column))")
    }

    func coalescedColumns(_ columns: [String], in table: String, qualifiedBy alias: String? = nil, fallback: SQLExpression = .null) -> SQLExpression {
        let available = columns.map { column($0, in: table, qualifiedBy: alias) }.filter { !$0.isNullLiteral }
        guard !available.isEmpty else {
            return fallback
        }

        if available.count == 1 {
            return available[0]
        }

        return .raw("COALESCE(\(available.map(\.sql).joined(separator: ", ")))")
    }
}

struct SQLExpression: Sendable, Equatable {
    var sql: String

    var isNullLiteral: Bool {
        sql == "NULL"
    }

    static let null = SQLExpression(sql: "NULL")
    static func raw(_ sql: String) -> SQLExpression {
        SQLExpression(sql: sql)
    }

    static func int(_ value: Int) -> SQLExpression {
        SQLExpression(sql: "\(value)")
    }

    static func text(_ value: String) -> SQLExpression {
        SQLExpression(sql: "'\(value.replacingOccurrences(of: "'", with: "''"))'")
    }
}
