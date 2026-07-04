import Foundation

public actor ReadOnlyMessagesStore: MessagesDatabaseReading {
    public let configuration: MessagesStoreConfiguration

    private var connection: SQLiteConnection?
    private var schema: MessagesDatabaseSchema?
    private var descriptor: MessagesStoreDescriptor?

    public init(configuration: MessagesStoreConfiguration = MessagesStoreConfiguration()) {
        self.configuration = configuration
    }

    public func openReadOnlyStore() async throws -> MessagesStoreDescriptor {
        try Task.checkCancellation()
        let opened = try openIfNeeded()
        return opened
    }

    func read<T: Sendable>(_ operation: @Sendable (SQLiteConnection, MessagesDatabaseSchema) throws -> T) async throws -> T {
        try Task.checkCancellation()
        _ = try openIfNeeded()

        guard let connection, let schema else {
            throw I2MessageError.databaseUnavailable(
                path: configuration.databaseURL.path,
                reason: "Messages store did not initialize."
            )
        }

        let result = try operation(connection, schema)
        try Task.checkCancellation()
        return result
    }

    func clampedLimit(_ requestedLimit: Int) -> Int {
        max(1, min(requestedLimit, configuration.maximumPageSize))
    }

    public func currentChangeToken() async -> MessagesChangeToken {
        MessagesStoreLocator.changeToken(for: configuration.databaseURL)
    }

    private func openIfNeeded() throws -> MessagesStoreDescriptor {
        if let descriptor {
            return descriptor
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: configuration.databaseURL.path) else {
            throw I2MessageError.databaseUnavailable(
                path: configuration.databaseURL.path,
                reason: "Messages database was not found."
            )
        }

        guard fileManager.isReadableFile(atPath: configuration.databaseURL.path) else {
            throw I2MessageError.permissionDenied(
                .fullDiskAccess,
                reason: "Messages database is not readable. Grant Full Disk Access to i2Message in System Settings."
            )
        }

        let openedConnection = try SQLiteConnection(readOnly: configuration.databaseURL)
        let inspectedSchema = try MessagesDatabaseSchema.inspect(openedConnection)
        try inspectedSchema.requireReadableMessagesSchema(databasePath: configuration.databaseURL.path)

        let openedDescriptor = MessagesStoreDescriptor(
            databaseURL: configuration.databaseURL,
            attachmentsDirectoryURL: configuration.attachmentsDirectoryURL,
            openedAt: Date(),
            isReadOnly: openedConnection.isReadOnly
        )

        guard openedDescriptor.isReadOnly else {
            throw I2MessageError.readOnlyStoreRequired
        }

        connection = openedConnection
        schema = inspectedSchema
        descriptor = openedDescriptor
        return openedDescriptor
    }
}
