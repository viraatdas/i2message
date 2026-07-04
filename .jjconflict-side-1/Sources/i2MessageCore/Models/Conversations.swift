import Foundation

public enum ConversationKind: String, Codable, Hashable, Sendable {
    case direct
    case group
    case unknown
}

public struct LastMessagePreview: Codable, Hashable, Sendable {
    public var messageID: MessageID?
    public var senderID: ContactID?
    public var text: String
    public var sentAt: Date
    public var hasAttachments: Bool

    public init(
        messageID: MessageID?,
        senderID: ContactID?,
        text: String,
        sentAt: Date,
        hasAttachments: Bool
    ) {
        self.messageID = messageID
        self.senderID = senderID
        self.text = text
        self.sentAt = sentAt
        self.hasAttachments = hasAttachments
    }
}

public struct Conversation: Identifiable, Codable, Hashable, Sendable {
    public var id: ConversationID
    public var title: String
    public var participants: [Contact]
    public var kind: ConversationKind
    public var service: MessageService
    public var unreadCount: Int
    public var pinnedRank: Int?
    public var isMuted: Bool
    public var isArchived: Bool
    public var lastMessage: LastMessagePreview?
    public var updatedAt: Date
    public var lastReadMessageID: MessageID?

    public init(
        id: ConversationID,
        title: String,
        participants: [Contact],
        kind: ConversationKind,
        service: MessageService,
        unreadCount: Int = 0,
        pinnedRank: Int? = nil,
        isMuted: Bool = false,
        isArchived: Bool = false,
        lastMessage: LastMessagePreview? = nil,
        updatedAt: Date,
        lastReadMessageID: MessageID? = nil
    ) {
        self.id = id
        self.title = title
        self.participants = participants
        self.kind = kind
        self.service = service
        self.unreadCount = unreadCount
        self.pinnedRank = pinnedRank
        self.isMuted = isMuted
        self.isArchived = isArchived
        self.lastMessage = lastMessage
        self.updatedAt = updatedAt
        self.lastReadMessageID = lastReadMessageID
    }
}

public struct ConversationFilter: Codable, Hashable, Sendable {
    public var query: String
    public var includeArchived: Bool
    public var unreadOnly: Bool
    public var pinnedOnly: Bool

    public init(
        query: String = "",
        includeArchived: Bool = false,
        unreadOnly: Bool = false,
        pinnedOnly: Bool = false
    ) {
        self.query = query
        self.includeArchived = includeArchived
        self.unreadOnly = unreadOnly
        self.pinnedOnly = pinnedOnly
    }
}
