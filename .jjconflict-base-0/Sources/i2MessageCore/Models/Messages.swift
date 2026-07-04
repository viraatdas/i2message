import Foundation

public enum MessageDirection: String, Codable, Hashable, Sendable {
    case incoming
    case outgoing
    case system
}

public enum MessageDeliveryStatus: String, Codable, Hashable, Sendable {
    case draft
    case queued
    case sending
    case sent
    case delivered
    case read
    case failed
    case unknown
}

public enum MessageBody: Codable, Hashable, Sendable {
    case text(String)
    case attributedMarkdown(String)
    case empty

    public var plainText: String {
        switch self {
        case .text(let value), .attributedMarkdown(let value):
            return value
        case .empty:
            return ""
        }
    }
}

public enum MessageReactionKind: String, Codable, Hashable, Sendable {
    case loved
    case liked
    case disliked
    case laughed
    case emphasized
    case questioned
    case custom
}

public struct MessageReaction: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: MessageReactionKind
    public var senderID: ContactID
    public var createdAt: Date
    public var displayText: String?

    public init(
        id: String,
        kind: MessageReactionKind,
        senderID: ContactID,
        createdAt: Date,
        displayText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.senderID = senderID
        self.createdAt = createdAt
        self.displayText = displayText
    }
}

public struct Message: Identifiable, Codable, Hashable, Sendable {
    public var id: MessageID
    public var conversationID: ConversationID
    public var senderID: ContactID?
    public var body: MessageBody
    public var direction: MessageDirection
    public var service: MessageService
    public var status: MessageDeliveryStatus
    public var sentAt: Date
    public var receivedAt: Date?
    public var attachments: [MessageAttachment]
    public var reactions: [MessageReaction]
    public var replyToMessageID: MessageID?
    public var isEdited: Bool
    public var isDeleted: Bool

    public init(
        id: MessageID,
        conversationID: ConversationID,
        senderID: ContactID?,
        body: MessageBody,
        direction: MessageDirection,
        service: MessageService,
        status: MessageDeliveryStatus,
        sentAt: Date,
        receivedAt: Date? = nil,
        attachments: [MessageAttachment] = [],
        reactions: [MessageReaction] = [],
        replyToMessageID: MessageID? = nil,
        isEdited: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.body = body
        self.direction = direction
        self.service = service
        self.status = status
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.attachments = attachments
        self.reactions = reactions
        self.replyToMessageID = replyToMessageID
        self.isEdited = isEdited
        self.isDeleted = isDeleted
    }
}
