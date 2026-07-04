import Foundation

public struct MessagesStoreConfiguration: Codable, Hashable, Sendable {
    public var databaseURL: URL
    public var attachmentsDirectoryURL: URL?
    public var pollInterval: TimeInterval
    public var maximumPageSize: Int

    public init(
        databaseURL: URL = MessagesStoreConfiguration.defaultDatabaseURL(),
        attachmentsDirectoryURL: URL? = MessagesStoreConfiguration.defaultAttachmentsDirectoryURL(),
        pollInterval: TimeInterval = 2,
        maximumPageSize: Int = 200
    ) {
        self.databaseURL = databaseURL
        self.attachmentsDirectoryURL = attachmentsDirectoryURL
        self.pollInterval = pollInterval
        self.maximumPageSize = maximumPageSize
    }

    public static func defaultDatabaseURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Messages", isDirectory: true)
            .appendingPathComponent("chat.db", isDirectory: false)
    }

    public static func defaultAttachmentsDirectoryURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Messages", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    public var storeDescriptor: MessagesStoreDescriptor {
        MessagesStoreDescriptor(
            databaseURL: databaseURL,
            attachmentsDirectoryURL: attachmentsDirectoryURL,
            openedAt: Date(),
            isReadOnly: true
        )
    }
}

public struct MessagesChangeToken: Codable, Hashable, Sendable {
    public var databaseFileSize: Int64?
    public var databaseModifiedAt: Date?
    public var walFileSize: Int64?
    public var walModifiedAt: Date?
    public var shmFileSize: Int64?
    public var shmModifiedAt: Date?

    public init(
        databaseFileSize: Int64?,
        databaseModifiedAt: Date?,
        walFileSize: Int64?,
        walModifiedAt: Date?,
        shmFileSize: Int64?,
        shmModifiedAt: Date?
    ) {
        self.databaseFileSize = databaseFileSize
        self.databaseModifiedAt = databaseModifiedAt
        self.walFileSize = walFileSize
        self.walModifiedAt = walModifiedAt
        self.shmFileSize = shmFileSize
        self.shmModifiedAt = shmModifiedAt
    }
}

public enum MessagesStoreLocator {
    public static func changeToken(for databaseURL: URL) -> MessagesChangeToken {
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: databaseURL.path + "-shm")

        return MessagesChangeToken(
            databaseFileSize: fileSize(databaseURL),
            databaseModifiedAt: modifiedAt(databaseURL),
            walFileSize: fileSize(walURL),
            walModifiedAt: modifiedAt(walURL),
            shmFileSize: fileSize(shmURL),
            shmModifiedAt: modifiedAt(shmURL)
        )
    }

    private static func attributes(_ url: URL) -> [FileAttributeKey: Any]? {
        try? FileManager.default.attributesOfItem(atPath: url.path)
    }

    private static func fileSize(_ url: URL) -> Int64? {
        if let value = attributes(url)?[.size] as? NSNumber {
            return value.int64Value
        }

        return attributes(url)?[.size] as? Int64
    }

    private static func modifiedAt(_ url: URL) -> Date? {
        attributes(url)?[.modificationDate] as? Date
    }
}
