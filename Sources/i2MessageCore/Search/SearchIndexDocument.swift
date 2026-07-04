import Foundation

public struct SearchIndexCorpus: Sendable {
    public var conversations: [Conversation]
    public var contacts: [Contact]
    public var messages: [Message]

    public init(
        conversations: [Conversation],
        contacts: [Contact],
        messages: [Message]
    ) {
        self.conversations = conversations
        self.contacts = contacts
        self.messages = messages
    }
}

public protocol SearchIndexCorpusProviding: Sendable {
    func searchIndexCorpus() async throws -> SearchIndexCorpus
}

public struct StaticSearchIndexCorpusProvider: SearchIndexCorpusProviding {
    public var corpus: SearchIndexCorpus

    public init(corpus: SearchIndexCorpus) {
        self.corpus = corpus
    }

    public func searchIndexCorpus() async throws -> SearchIndexCorpus {
        corpus
    }
}

public struct LocalSearchFilters: Codable, Hashable, Sendable {
    public var conversationID: ConversationID?
    public var senderID: ContactID?
    public var sentAfter: Date?
    public var sentBefore: Date?
    public var service: MessageService?
    public var includeAttachments: Bool

    public init(
        conversationID: ConversationID? = nil,
        senderID: ContactID? = nil,
        sentAfter: Date? = nil,
        sentBefore: Date? = nil,
        service: MessageService? = nil,
        includeAttachments: Bool = true
    ) {
        self.conversationID = conversationID
        self.senderID = senderID
        self.sentAfter = sentAfter
        self.sentBefore = sentBefore
        self.service = service
        self.includeAttachments = includeAttachments
    }

    init(exactQuery: ExactSearchQuery) {
        self.init(
            conversationID: exactQuery.conversationID,
            senderID: exactQuery.senderID,
            sentAfter: exactQuery.sentAfter,
            sentBefore: exactQuery.sentBefore,
            includeAttachments: exactQuery.includeAttachments
        )
    }
}

public struct HybridSearchQuery: Codable, Hashable, Sendable {
    public var text: String
    public var filters: LocalSearchFilters
    public var exactWeight: Double
    public var semanticWeight: Double
    public var minimumSemanticSimilarity: Double

    public init(
        text: String,
        filters: LocalSearchFilters = LocalSearchFilters(),
        exactWeight: Double = 0.68,
        semanticWeight: Double = 0.32,
        minimumSemanticSimilarity: Double = 0.42
    ) {
        self.text = text
        self.filters = filters
        self.exactWeight = exactWeight
        self.semanticWeight = semanticWeight
        self.minimumSemanticSimilarity = minimumSemanticSimilarity
    }
}

public struct SearchSuggestion: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var kind: SearchResultKind
    public var subtitle: String
    public var score: Double

    public init(id: String, text: String, kind: SearchResultKind, subtitle: String, score: Double) {
        self.id = id
        self.text = text
        self.kind = kind
        self.subtitle = subtitle
        self.score = score
    }
}

public struct RecentSearch: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var mode: SearchMode
    public var createdAt: Date

    public init(id: String, text: String, mode: SearchMode, createdAt: Date) {
        self.id = id
        self.text = text
        self.mode = mode
        self.createdAt = createdAt
    }
}

public struct SearchNavigationTarget: Codable, Hashable, Sendable {
    public var conversationID: ConversationID
    public var messageID: MessageID?
    public var attachmentID: AttachmentID?
    public var preferredAnchor: MessageID?
    public var resultKind: SearchResultKind

    public init(
        conversationID: ConversationID,
        messageID: MessageID? = nil,
        attachmentID: AttachmentID? = nil,
        preferredAnchor: MessageID? = nil,
        resultKind: SearchResultKind
    ) {
        self.conversationID = conversationID
        self.messageID = messageID
        self.attachmentID = attachmentID
        self.preferredAnchor = preferredAnchor
        self.resultKind = resultKind
    }
}

public struct LocalSearchIndexState: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var documentCount: Int
    public var semanticEmbeddingCount: Int
    public var pendingSemanticEmbeddingCount: Int

    public init(
        schemaVersion: Int,
        documentCount: Int,
        semanticEmbeddingCount: Int,
        pendingSemanticEmbeddingCount: Int
    ) {
        self.schemaVersion = schemaVersion
        self.documentCount = documentCount
        self.semanticEmbeddingCount = semanticEmbeddingCount
        self.pendingSemanticEmbeddingCount = pendingSemanticEmbeddingCount
    }
}

struct SearchIndexDocument: Hashable, Sendable {
    var id: String
    var kind: SearchResultKind
    var conversationID: ConversationID?
    var messageID: MessageID?
    var contactID: ContactID?
    var attachmentID: AttachmentID?
    var title: String
    var subtitle: String
    var body: String
    var service: MessageService?
    var senderID: ContactID?
    var date: Date?
    var hash: String

    var semanticText: String {
        [title, subtitle, body]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum SearchDocumentBuilder {
    static func documents(from corpus: SearchIndexCorpus) -> [SearchIndexDocument] {
        let conversationsByID = Dictionary(uniqueKeysWithValues: corpus.conversations.map { ($0.id, $0) })
        let contactsByID = Dictionary(uniqueKeysWithValues: corpus.contacts.map { ($0.id, $0) })

        var documents: [SearchIndexDocument] = []
        documents.reserveCapacity(corpus.conversations.count + corpus.contacts.count + corpus.messages.count)

        documents.append(contentsOf: corpus.conversations.map { conversation in
            conversationDocument(conversation)
        })

        documents.append(contentsOf: corpus.contacts.map { contact in
            contactDocument(contact)
        })

        for message in corpus.messages where !message.isDeleted {
            documents.append(messageDocument(message, conversation: conversationsByID[message.conversationID], contactsByID: contactsByID))

            for attachment in message.attachments {
                documents.append(attachmentDocument(attachment, message: message, conversation: conversationsByID[message.conversationID]))
            }
        }

        return documents.sorted { $0.id < $1.id }
    }

    static func corpusSignature(for documents: [SearchIndexDocument]) -> String {
        StableHash.digest(documents.map { "\($0.id):\($0.hash)" }.joined(separator: "|"))
    }

    private static func conversationDocument(_ conversation: Conversation) -> SearchIndexDocument {
        let participants = conversation.participants.map(\.displayName).joined(separator: ", ")
        let preview = conversation.lastMessage?.text ?? ""
        let body = [conversation.title, participants, preview, conversation.service.rawValue]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return SearchIndexDocument(
            id: "conversation:\(conversation.id.rawValue)",
            kind: .conversation,
            conversationID: conversation.id,
            messageID: nil,
            contactID: nil,
            attachmentID: nil,
            title: conversation.title,
            subtitle: participants,
            body: body,
            service: conversation.service,
            senderID: nil,
            date: conversation.updatedAt,
            hash: StableHash.digest(body)
        )
    }

    private static func contactDocument(_ contact: Contact) -> SearchIndexDocument {
        let handles = contact.handles
            .flatMap { [$0.value, $0.normalizedValue, $0.service.rawValue] }
            .joined(separator: " ")
        let body = [contact.displayName, handles]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return SearchIndexDocument(
            id: "contact:\(contact.id.rawValue)",
            kind: .contact,
            conversationID: nil,
            messageID: nil,
            contactID: contact.id,
            attachmentID: nil,
            title: contact.displayName,
            subtitle: contact.handles.map(\.value).joined(separator: ", "),
            body: body,
            service: contact.handles.first?.service,
            senderID: contact.id,
            date: contact.lastResolvedAt,
            hash: StableHash.digest(body)
        )
    }

    private static func messageDocument(
        _ message: Message,
        conversation: Conversation?,
        contactsByID: [ContactID: Contact]
    ) -> SearchIndexDocument {
        let sender = message.senderID.flatMap { contactsByID[$0]?.displayName } ?? ""
        let reactionText = message.reactions
            .map { reaction in
                [reaction.kind.rawValue, reaction.displayText].compactMap { $0 }.joined(separator: " ")
            }
            .joined(separator: " ")
        let body = [message.body.plainText, reactionText, message.service.rawValue]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return SearchIndexDocument(
            id: "message:\(message.id.rawValue)",
            kind: .message,
            conversationID: message.conversationID,
            messageID: message.id,
            contactID: message.senderID,
            attachmentID: nil,
            title: conversation?.title ?? "Conversation",
            subtitle: sender,
            body: body,
            service: message.service,
            senderID: message.senderID,
            date: message.sentAt,
            hash: StableHash.digest(body)
        )
    }

    private static func attachmentDocument(
        _ attachment: MessageAttachment,
        message: Message,
        conversation: Conversation?
    ) -> SearchIndexDocument {
        let details = [
            attachment.kind.rawValue,
            attachment.uniformTypeIdentifier,
            attachment.byteCount.map(String.init)
        ].compactMap { $0 }.joined(separator: " ")
        let body = [attachment.filename, details, message.body.plainText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return SearchIndexDocument(
            id: "attachment:\(attachment.id.rawValue)",
            kind: .attachment,
            conversationID: message.conversationID,
            messageID: message.id,
            contactID: message.senderID,
            attachmentID: attachment.id,
            title: attachment.filename,
            subtitle: conversation?.title ?? details,
            body: body,
            service: message.service,
            senderID: message.senderID,
            date: message.sentAt,
            hash: StableHash.digest(body)
        )
    }
}

enum StableHash {
    static func digest(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
