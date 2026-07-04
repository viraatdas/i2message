import Foundation
import SQLite3

enum SQLiteBindValue: Sendable {
    case null
    case int(Int)
    case int64(Int64)
    case double(Double)
    case text(String)
    case data(Data)
}

enum SQLiteColumnValue: Sendable, Equatable {
    case null
    case int64(Int64)
    case double(Double)
    case text(String)
    case data(Data)

    var int: Int? {
        guard case .int64(let value) = self else {
            return nil
        }

        return Int(value)
    }

    var int64: Int64? {
        guard case .int64(let value) = self else {
            return nil
        }

        return value
    }

    var bool: Bool? {
        guard case .int64(let value) = self else {
            return nil
        }

        return value != 0
    }

    var double: Double? {
        switch self {
        case .double(let value):
            return value
        case .int64(let value):
            return Double(value)
        default:
            return nil
        }
    }

    var string: String? {
        guard case .text(let value) = self else {
            return nil
        }

        return value
    }

    var data: Data? {
        guard case .data(let value) = self else {
            return nil
        }

        return value
    }
}

struct SQLiteRow: Sendable, Equatable {
    private var values: [String: SQLiteColumnValue]

    init(values: [String: SQLiteColumnValue]) {
        self.values = values
    }

    subscript(_ column: String) -> SQLiteColumnValue {
        values[column] ?? .null
    }

    func hasColumn(_ column: String) -> Bool {
        values[column] != nil
    }
}

final class SQLiteConnection: @unchecked Sendable {
    let url: URL
    private var database: OpaquePointer?

    init(readOnly url: URL) throws {
        self.url = url

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(url.path, &database, flags, nil)

        guard result == SQLITE_OK, let database else {
            let reason = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
                ?? "SQLite could not open the database."
            if let database {
                sqlite3_close(database)
            }
            throw I2MessageError.databaseUnavailable(path: url.path, reason: reason)
        }

        guard sqlite3_db_readonly(database, "main") == 1 else {
            throw I2MessageError.readOnlyStoreRequired
        }

        try execute("PRAGMA query_only = ON")
        try execute("PRAGMA foreign_keys = OFF")
        try execute("PRAGMA temp_store = MEMORY")
        try execute("PRAGMA busy_timeout = 1500")
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    var isReadOnly: Bool {
        guard let database else {
            return false
        }

        return sqlite3_db_readonly(database, "main") == 1
    }

    func query(_ sql: String, _ bindings: [SQLiteBindValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }

        var rows: [SQLiteRow] = []

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return rows
            }

            guard result == SQLITE_ROW else {
                throw lastError(fallback: "SQLite query failed.")
            }

            rows.append(row(from: statement))
        }
    }

    func scalar(_ sql: String, _ bindings: [SQLiteBindValue] = []) throws -> SQLiteColumnValue {
        try query(sql, bindings).first?["value"] ?? .null
    }

    func execute(_ sql: String, _ bindings: [SQLiteBindValue] = []) throws {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw lastError(fallback: "SQLite statement failed.")
        }
    }

    func tableExists(_ table: String) throws -> Bool {
        let rows = try query(
            """
            SELECT 1 AS value
            FROM sqlite_master
            WHERE type = 'table' AND name = ?
            LIMIT 1
            """,
            [.text(table)]
        )

        return !rows.isEmpty
    }

    func columns(in table: String) throws -> Set<String> {
        let quotedTable = SQLiteIdentifier.quote(table)
        let rows = try query("PRAGMA table_info(\(quotedTable))")
        return Set(rows.compactMap { $0["name"].string })
    }

    func userVersion() throws -> Int {
        try query("PRAGMA user_version").first?["user_version"].int ?? 0
    }

    private func prepare(_ sql: String, _ bindings: [SQLiteBindValue]) throws -> OpaquePointer {
        guard let database else {
            throw I2MessageError.databaseUnavailable(path: url.path, reason: "SQLite connection is closed.")
        }

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw lastError(fallback: "SQLite statement could not be prepared.")
        }

        do {
            try bind(bindings, to: statement)
            return statement
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }

    private func bind(_ bindings: [SQLiteBindValue], to statement: OpaquePointer) throws {
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32

            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .int(let value):
                result = sqlite3_bind_int64(statement, index, Int64(value))
            case .int64(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, SQLiteDestructor.transient)
            case .data(let data):
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), SQLiteDestructor.transient)
                }
            }

            guard result == SQLITE_OK else {
                throw lastError(fallback: "SQLite binding failed.")
            }
        }
    }

    private func row(from statement: OpaquePointer) -> SQLiteRow {
        let count = sqlite3_column_count(statement)
        var values: [String: SQLiteColumnValue] = [:]
        values.reserveCapacity(Int(count))

        for index in 0..<count {
            guard let columnNamePointer = sqlite3_column_name(statement, index) else {
                continue
            }

            let columnName = String(cString: columnNamePointer)
            values[columnName] = value(from: statement, at: index)
        }

        return SQLiteRow(values: values)
    }

    private func value(from statement: OpaquePointer, at index: Int32) -> SQLiteColumnValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .int64(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else {
                return .null
            }
            return .text(String(cString: pointer))
        case SQLITE_BLOB:
            guard let pointer = sqlite3_column_blob(statement, index) else {
                return .data(Data())
            }
            let byteCount = Int(sqlite3_column_bytes(statement, index))
            return .data(Data(bytes: pointer, count: byteCount))
        default:
            return .null
        }
    }

    private func lastError(fallback: String) -> I2MessageError {
        let reason = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? fallback
        return I2MessageError.databaseUnavailable(path: url.path, reason: reason)
    }
}

enum SQLiteIdentifier {
    static func quote(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private enum SQLiteDestructor {
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
