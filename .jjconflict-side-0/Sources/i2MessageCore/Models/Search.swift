import Foundation

public enum SearchMode: String, Codable, Hashable, Sendable {
    case exact
    case semantic
    case hybrid
}

public struct ExactSearchQuery: Codable, Hashable, Sendable {
    public var text: String
    public var conversationID: ConversationID?
    public var senderID: ContactID?
    public var sentAfter: Date?
    public var sentBefore: Date?
    public var includeAttachments: Bool

    public init(
        text: String,
        conversationID: ConversationID? = nil,
        senderID: ContactID? = nil,
        sentAfter: Date? = nil,
        sentBefore: Date? = nil,
        includeAttachments: Bool = true
    ) {
        self.text = text
        self.conversationID = conversationID
        self.senderID = senderID
        self.sentAfter = sentAfter
        self.sentBefore = sentBefore
        self.includeAttachments = includeAttachments
    }
}

public struct SemanticSearchQuery: Codable, Hashable, Sendable {
    public var text: String
    public var conversationID: ConversationID?
    public var limit: Int
    public var minimumSimilarity: Double

    public init(
        text: String,
        conversationID: ConversationID? = nil,
        limit: Int = 20,
        minimumSimilarity: Double = 0.72
    ) {
        self.text = text
        self.conversationID = conversationID
        self.limit = limit
        self.minimumSimilarity = minimumSimilarity
    }
}

public enum SearchResultKind: String, Codable, Hashable, Sendable {
    case message
    case conversation
    case contact
    case attachment
    case semanticSnippet
}

public struct TextRange: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public struct SearchResult: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: SearchResultKind
    public var conversationID: ConversationID?
    public var messageID: MessageID?
    public var contactID: ContactID?
    public var attachmentID: AttachmentID?
    public var title: String
    public var subtitle: String
    public var snippet: String
    public var matchedRanges: [TextRange]
    public var score: Double
    public var date: Date?

    public init(
        id: String,
        kind: SearchResultKind,
        conversationID: ConversationID? = nil,
        messageID: MessageID? = nil,
        contactID: ContactID? = nil,
        attachmentID: AttachmentID? = nil,
        title: String,
        subtitle: String,
        snippet: String,
        matchedRanges: [TextRange] = [],
        score: Double,
        date: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.conversationID = conversationID
        self.messageID = messageID
        self.contactID = contactID
        self.attachmentID = attachmentID
        self.title = title
        self.subtitle = subtitle
        self.snippet = snippet
        self.matchedRanges = matchedRanges
        self.score = score
        self.date = date
    }
}

public struct SemanticSnippet: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var conversationID: ConversationID
    public var sourceMessageIDs: [MessageID]
    public var text: String
    public var similarity: Double
    public var embeddingModelIdentifier: String
    public var generatedAt: Date

    public init(
        id: String,
        conversationID: ConversationID,
        sourceMessageIDs: [MessageID],
        text: String,
        similarity: Double,
        embeddingModelIdentifier: String,
        generatedAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.sourceMessageIDs = sourceMessageIDs
        self.text = text
        self.similarity = similarity
        self.embeddingModelIdentifier = embeddingModelIdentifier
        self.generatedAt = generatedAt
    }
}
