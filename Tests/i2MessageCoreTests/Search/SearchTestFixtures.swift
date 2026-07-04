import Foundation
@testable import i2MessageCore

enum SearchTestFixtures {
    static let baseDate = Date(timeIntervalSinceReferenceDate: 810_000_000)

    static let currentUser = Contact(
        id: "contact.me",
        displayName: "You",
        handles: [
            ContactHandle(
                value: "you@example.com",
                normalizedValue: "you@example.com",
                kind: .emailAddress,
                service: .iMessage
            )
        ],
        isCurrentUser: true,
        lastResolvedAt: baseDate
    )

    static let maya = Contact(
        id: "contact.maya",
        displayName: "Maya Chen",
        handles: [
            ContactHandle(
                value: "+1 (415) 555-0134",
                normalizedValue: "+14155550134",
                kind: .phoneNumber,
                service: .iMessage
            )
        ],
        lastResolvedAt: baseDate
    )

    static let ava = Contact(
        id: "contact.ava",
        displayName: "Ava Patel",
        handles: [
            ContactHandle(
                value: "ava@example.com",
                normalizedValue: "ava@example.com",
                kind: .emailAddress,
                service: .sms
            )
        ],
        lastResolvedAt: baseDate
    )

    static func service(
        corpus: SearchIndexCorpus,
        batchSize: Int = 100,
        embedder: any SemanticEmbeddingProviding = HashingSemanticEmbedder()
    ) -> LocalSearchService {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("i2message-search-tests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("index.sqlite")
        return LocalSearchService(
            indexURL: url,
            corpusProvider: StaticSearchIndexCorpusProvider(corpus: corpus),
            embedder: embedder,
            indexingBatchSize: batchSize,
            semanticCandidateLimit: 50_000
        )
    }

    static func focusedCorpus() -> SearchIndexCorpus {
        let design = Conversation(
            id: "conversation.design",
            title: "Design review",
            participants: [maya, currentUser],
            kind: .direct,
            service: .iMessage,
            lastMessage: LastMessagePreview(
                messageID: "message.design.3",
                senderID: maya.id,
                text: "The adapter search flow is much faster now.",
                sentAt: baseDate.addingTimeInterval(-60),
                hasAttachments: false
            ),
            updatedAt: baseDate.addingTimeInterval(-60)
        )
        let receipts = Conversation(
            id: "conversation.receipts",
            title: "Receipts",
            participants: [ava, currentUser],
            kind: .direct,
            service: .sms,
            lastMessage: LastMessagePreview(
                messageID: "message.receipts.1",
                senderID: ava.id,
                text: "Sent the invoice PDF from last week.",
                sentAt: baseDate.addingTimeInterval(-600),
                hasAttachments: true
            ),
            updatedAt: baseDate.addingTimeInterval(-600)
        )
        let lunch = Conversation(
            id: "conversation.lunch",
            title: "Lunch plans",
            participants: [maya, currentUser],
            kind: .direct,
            service: .iMessage,
            lastMessage: nil,
            updatedAt: baseDate.addingTimeInterval(-900)
        )

        let messages = [
            Message(
                id: "message.design.1",
                conversationID: design.id,
                senderID: currentUser.id,
                body: .text("Exact search should find adapter notes inside long histories."),
                direction: .outgoing,
                service: .iMessage,
                status: .sent,
                sentAt: baseDate.addingTimeInterval(-300)
            ),
            Message(
                id: "message.design.2",
                conversationID: design.id,
                senderID: maya.id,
                body: .text("Keyboard navigation and adapter search need to stay fast."),
                direction: .incoming,
                service: .iMessage,
                status: .delivered,
                sentAt: baseDate.addingTimeInterval(-200)
            ),
            Message(
                id: "message.design.3",
                conversationID: design.id,
                senderID: maya.id,
                body: .text("The adapter search flow is much faster now."),
                direction: .incoming,
                service: .iMessage,
                status: .delivered,
                sentAt: baseDate.addingTimeInterval(-60)
            ),
            Message(
                id: "message.receipts.1",
                conversationID: receipts.id,
                senderID: ava.id,
                body: .text("Sent the invoice PDF from last week."),
                direction: .incoming,
                service: .sms,
                status: .delivered,
                sentAt: baseDate.addingTimeInterval(-600),
                attachments: [
                    MessageAttachment(
                        id: "attachment.invoice",
                        messageID: "message.receipts.1",
                        kind: .file,
                        filename: "Invoice-Last-Week.pdf",
                        uniformTypeIdentifier: "com.adobe.pdf",
                        byteCount: 241_920
                    )
                ]
            ),
            Message(
                id: "message.lunch.1",
                conversationID: lunch.id,
                senderID: maya.id,
                body: .text("Lunch at noon works. I can bring coffee too."),
                direction: .incoming,
                service: .iMessage,
                status: .delivered,
                sentAt: baseDate.addingTimeInterval(-900)
            )
        ]

        return SearchIndexCorpus(
            conversations: [design, receipts, lunch],
            contacts: [currentUser, maya, ava],
            messages: messages
        )
    }

    static func largeCorpus(messageCount: Int = 8_000, needleEvery: Int = 40) -> SearchIndexCorpus {
        let contacts = [currentUser, maya, ava]
        let conversations = (0..<24).map { index in
            Conversation(
                id: ConversationID(rawValue: "conversation.synthetic.\(index)"),
                title: "Synthetic Thread \(index)",
                participants: [contacts[index % contacts.count], currentUser],
                kind: .direct,
                service: index.isMultiple(of: 3) ? .sms : .iMessage,
                lastMessage: nil,
                updatedAt: baseDate.addingTimeInterval(TimeInterval(-index * 60))
            )
        }

        let messages = (0..<messageCount).map { index in
            let conversation = conversations[index % conversations.count]
            let hasNeedle = index.isMultiple(of: needleEvery)
            let body = hasNeedle
                ? "Synthetic searchable needle phrase number \(index) with invoice details and fast pagination."
                : "Synthetic filler message \(index) about weekend plans and ordinary chat history."

            return Message(
                id: MessageID(rawValue: "message.synthetic.\(index)"),
                conversationID: conversation.id,
                senderID: contacts[index % contacts.count].id,
                body: .text(body),
                direction: index.isMultiple(of: 2) ? .incoming : .outgoing,
                service: conversation.service,
                status: .delivered,
                sentAt: baseDate.addingTimeInterval(TimeInterval(-index))
            )
        }

        return SearchIndexCorpus(conversations: conversations, contacts: contacts, messages: messages)
    }
}

actor SlowHashingEmbedder: SemanticEmbeddingProviding {
    nonisolated let modelIdentifier = "slow-local-hashing-semantic-test"
    nonisolated let dimension = 64
    private let fallback = HashingSemanticEmbedder(dimension: 64, modelIdentifier: "slow-local-hashing-semantic-test")

    func embedding(for text: String) async throws -> [Float] {
        try await Task.sleep(nanoseconds: 1_000_000)
        return try await fallback.embedding(for: text)
    }
}
