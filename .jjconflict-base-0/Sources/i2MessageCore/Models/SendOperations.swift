import Foundation

public enum SendTarget: Codable, Hashable, Sendable {
    case existingConversation(ConversationID)
    case handles([ContactHandle])
}

public struct DraftAttachment: Identifiable, Codable, Hashable, Sendable {
    public var id: AttachmentID
    public var fileURL: URL
    public var filename: String
    public var uniformTypeIdentifier: String?

    public init(
        id: AttachmentID,
        fileURL: URL,
        filename: String,
        uniformTypeIdentifier: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.filename = filename
        self.uniformTypeIdentifier = uniformTypeIdentifier
    }
}

public struct MessageDraft: Codable, Hashable, Sendable {
    public var target: SendTarget
    public var text: String
    public var attachments: [DraftAttachment]
    public var replyToMessageID: MessageID?
    public var requestedService: MessageService?

    public init(
        target: SendTarget,
        text: String,
        attachments: [DraftAttachment] = [],
        replyToMessageID: MessageID? = nil,
        requestedService: MessageService? = nil
    ) {
        self.target = target
        self.text = text
        self.attachments = attachments
        self.replyToMessageID = replyToMessageID
        self.requestedService = requestedService
    }
}

public enum SendOperationState: String, Codable, Hashable, Sendable {
    case validating
    case awaitingPermission
    case sending
    case sent
    case failed
    case unsupported
}

public struct SendOperation: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var draft: MessageDraft
    public var state: SendOperationState
    public var createdAt: Date
    public var updatedAt: Date
    public var failureReason: String?

    public init(
        id: String,
        draft: MessageDraft,
        state: SendOperationState,
        createdAt: Date,
        updatedAt: Date,
        failureReason: String? = nil
    ) {
        self.id = id
        self.draft = draft
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.failureReason = failureReason
    }
}

public struct SendReceipt: Codable, Hashable, Sendable {
    public var operationID: String
    public var conversationID: ConversationID?
    public var messageID: MessageID?
    public var sentAt: Date

    public init(
        operationID: String,
        conversationID: ConversationID?,
        messageID: MessageID?,
        sentAt: Date
    ) {
        self.operationID = operationID
        self.conversationID = conversationID
        self.messageID = messageID
        self.sentAt = sentAt
    }
}
