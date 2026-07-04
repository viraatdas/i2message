import Foundation

public enum MessagesStoreDiagnosticSeverity: String, Codable, Hashable, Sendable {
    case info
    case warning
    case error
}

public enum MessagesStoreDiagnosticCode: String, Codable, Hashable, Sendable {
    case ok
    case databaseMissing
    case fullDiskAccessLikelyMissing
    case unreadableDatabase
    case corruptDatabase
    case unsupportedSchema
    case readOnlyOpenFailed
}

public struct MessagesStoreDiagnostic: Identifiable, Codable, Hashable, Sendable {
    public var id: String { code.rawValue }

    public var code: MessagesStoreDiagnosticCode
    public var severity: MessagesStoreDiagnosticSeverity
    public var message: String
    public var recoverySuggestion: String?

    public init(
        code: MessagesStoreDiagnosticCode,
        severity: MessagesStoreDiagnosticSeverity,
        message: String,
        recoverySuggestion: String? = nil
    ) {
        self.code = code
        self.severity = severity
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

public struct MessagesStoreDiagnostics: Codable, Hashable, Sendable {
    public var databaseURL: URL
    public var checkedAt: Date
    public var schemaVersion: Int?
    public var isReadable: Bool
    public var canOpenReadOnly: Bool
    public var diagnostics: [MessagesStoreDiagnostic]

    public init(
        databaseURL: URL,
        checkedAt: Date,
        schemaVersion: Int?,
        isReadable: Bool,
        canOpenReadOnly: Bool,
        diagnostics: [MessagesStoreDiagnostic]
    ) {
        self.databaseURL = databaseURL
        self.checkedAt = checkedAt
        self.schemaVersion = schemaVersion
        self.isReadable = isReadable
        self.canOpenReadOnly = canOpenReadOnly
        self.diagnostics = diagnostics
    }

    public var isUsable: Bool {
        canOpenReadOnly && !diagnostics.contains { $0.severity == .error }
    }
}

public actor MessagesStoreDiagnosticService {
    private let configuration: MessagesStoreConfiguration
    private let now: @Sendable () -> Date

    public init(configuration: MessagesStoreConfiguration = MessagesStoreConfiguration(), now: @escaping @Sendable () -> Date = Date.init) {
        self.configuration = configuration
        self.now = now
    }

    public func runDiagnostics() async -> MessagesStoreDiagnostics {
        let databaseURL = configuration.databaseURL
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return MessagesStoreDiagnostics(
                databaseURL: databaseURL,
                checkedAt: now(),
                schemaVersion: nil,
                isReadable: false,
                canOpenReadOnly: false,
                diagnostics: [
                    MessagesStoreDiagnostic(
                        code: .databaseMissing,
                        severity: .error,
                        message: "Messages database was not found.",
                        recoverySuggestion: "Choose a chat.db file or use the default ~/Library/Messages/chat.db location."
                    )
                ]
            )
        }

        guard fileManager.isReadableFile(atPath: databaseURL.path) else {
            return MessagesStoreDiagnostics(
                databaseURL: databaseURL,
                checkedAt: now(),
                schemaVersion: nil,
                isReadable: false,
                canOpenReadOnly: false,
                diagnostics: [
                    MessagesStoreDiagnostic(
                        code: .fullDiskAccessLikelyMissing,
                        severity: .error,
                        message: "Messages database exists but is not readable.",
                        recoverySuggestion: "Grant Full Disk Access to i2Message in System Settings, then relaunch the app."
                    )
                ]
            )
        }

        do {
            let connection = try SQLiteConnection(readOnly: databaseURL)
            let schema = try MessagesDatabaseSchema.inspect(connection)
            let schemaDiagnostics = schema.requiredTableDiagnostics()

            return MessagesStoreDiagnostics(
                databaseURL: databaseURL,
                checkedAt: now(),
                schemaVersion: try? connection.userVersion(),
                isReadable: true,
                canOpenReadOnly: connection.isReadOnly,
                diagnostics: schemaDiagnostics.isEmpty
                    ? [
                        MessagesStoreDiagnostic(
                            code: .ok,
                            severity: .info,
                            message: "Messages database can be opened read-only."
                        )
                    ]
                    : schemaDiagnostics
            )
        } catch let error as I2MessageError {
            return diagnostics(for: error, databaseURL: databaseURL)
        } catch {
            return MessagesStoreDiagnostics(
                databaseURL: databaseURL,
                checkedAt: now(),
                schemaVersion: nil,
                isReadable: true,
                canOpenReadOnly: false,
                diagnostics: [
                    MessagesStoreDiagnostic(
                        code: .readOnlyOpenFailed,
                        severity: .error,
                        message: "Messages database could not be opened read-only.",
                        recoverySuggestion: error.localizedDescription
                    )
                ]
            )
        }
    }

    private func diagnostics(for error: I2MessageError, databaseURL: URL) -> MessagesStoreDiagnostics {
        let diagnostic: MessagesStoreDiagnostic

        switch error {
        case .readOnlyStoreRequired:
            diagnostic = MessagesStoreDiagnostic(
                code: .readOnlyOpenFailed,
                severity: .error,
                message: "Messages database did not open as a read-only store.",
                recoverySuggestion: "i2Message refuses to use writable SQLite connections for Messages data."
            )
        case .databaseUnavailable(_, let reason) where reason.localizedCaseInsensitiveContains("not a database"):
            diagnostic = MessagesStoreDiagnostic(
                code: .corruptDatabase,
                severity: .error,
                message: "Messages database appears corrupt or is not a SQLite database.",
                recoverySuggestion: reason
            )
        case .databaseUnavailable(_, let reason) where reason.localizedCaseInsensitiveContains("authorization")
            || reason.localizedCaseInsensitiveContains("operation not permitted")
            || reason.localizedCaseInsensitiveContains("permission"):
            diagnostic = MessagesStoreDiagnostic(
                code: .fullDiskAccessLikelyMissing,
                severity: .error,
                message: "Messages database could not be opened because macOS denied access.",
                recoverySuggestion: "Grant Full Disk Access to i2Message in System Settings, then relaunch the app."
            )
        case .databaseUnavailable(_, let reason):
            diagnostic = MessagesStoreDiagnostic(
                code: .readOnlyOpenFailed,
                severity: .error,
                message: "Messages database could not be opened read-only.",
                recoverySuggestion: reason
            )
        default:
            diagnostic = MessagesStoreDiagnostic(
                code: .readOnlyOpenFailed,
                severity: .error,
                message: "Messages database could not be inspected.",
                recoverySuggestion: error.localizedDescription
            )
        }

        return MessagesStoreDiagnostics(
            databaseURL: databaseURL,
            checkedAt: now(),
            schemaVersion: nil,
            isReadable: FileManager.default.isReadableFile(atPath: databaseURL.path),
            canOpenReadOnly: false,
            diagnostics: [diagnostic]
        )
    }
}
