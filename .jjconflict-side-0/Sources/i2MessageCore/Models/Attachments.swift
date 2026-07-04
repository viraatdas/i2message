import Foundation

public enum AttachmentKind: String, Codable, Hashable, Sendable {
    case image
    case video
    case audio
    case file
    case sticker
    case tapback
    case unknown
}

public enum AttachmentTransferState: String, Codable, Hashable, Sendable {
    case local
    case remotePlaceholder
    case downloading
    case failed
}

public struct AttachmentDimensions: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct MessageAttachment: Identifiable, Codable, Hashable, Sendable {
    public var id: AttachmentID
    public var messageID: MessageID?
    public var kind: AttachmentKind
    public var filename: String
    public var uniformTypeIdentifier: String?
    public var byteCount: Int64?
    public var fileURL: URL?
    public var thumbnailURL: URL?
    public var dimensions: AttachmentDimensions?
    public var duration: TimeInterval?
    public var transferState: AttachmentTransferState

    public init(
        id: AttachmentID,
        messageID: MessageID? = nil,
        kind: AttachmentKind,
        filename: String,
        uniformTypeIdentifier: String? = nil,
        byteCount: Int64? = nil,
        fileURL: URL? = nil,
        thumbnailURL: URL? = nil,
        dimensions: AttachmentDimensions? = nil,
        duration: TimeInterval? = nil,
        transferState: AttachmentTransferState = .local
    ) {
        self.id = id
        self.messageID = messageID
        self.kind = kind
        self.filename = filename
        self.uniformTypeIdentifier = uniformTypeIdentifier
        self.byteCount = byteCount
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.dimensions = dimensions
        self.duration = duration
        self.transferState = transferState
    }
}
