import Foundation
import i2MessageCore

struct AppDependencies: Sendable {
    var isLiveData: Bool
    var seed: MockAppDataset
    var conversationRepository: any ConversationRepository
    var messageRepository: any MessageRepository
    var contactProvider: any ContactProviding
    var searchProvider: any SearchProviding
    var searchIndexer: any SearchIndexing
    var permissionManager: any PermissionManaging
    var messagingActions: (any MessagingActionServicing)?
    var settingsStore: any SettingsStoring
    var messageSender: any MessageSending

    static func mock(delayNanoseconds: UInt64 = 55_000_000) -> AppDependencies {
        let dataset = MockAppDataset.rich
        return fixture(dataset: dataset, delayNanoseconds: delayNanoseconds)
    }

    static func fixture(dataset: MockAppDataset, delayNanoseconds: UInt64 = 55_000_000) -> AppDependencies {
        return AppDependencies(
            isLiveData: false,
            seed: dataset,
            conversationRepository: MockConversationRepository(dataset: dataset, delayNanoseconds: delayNanoseconds),
            messageRepository: MockMessageRepository(dataset: dataset, delayNanoseconds: delayNanoseconds),
            contactProvider: MockContactProvider(dataset: dataset, delayNanoseconds: delayNanoseconds),
            searchProvider: MockSearchProvider(dataset: dataset, delayNanoseconds: delayNanoseconds),
            searchIndexer: MockSearchIndexer(delayNanoseconds: delayNanoseconds),
            permissionManager: MockPermissionManager(),
            messagingActions: nil,
            settingsStore: MockSettingsStore(),
            messageSender: MockMessageSender(delayNanoseconds: delayNanoseconds)
        )
    }

    static func indexedFixture(
        dataset: MockAppDataset,
        indexURL: URL,
        embedder: any SemanticEmbeddingProviding = HashingSemanticEmbedder(),
        delayNanoseconds: UInt64 = 0
    ) -> AppDependencies {
        let corpus = SearchIndexCorpus(
            conversations: dataset.conversations,
            contacts: dataset.contacts,
            messages: dataset.allMessages
        )
        let searchService = LocalSearchService(
            indexURL: indexURL,
            corpusProvider: StaticSearchIndexCorpusProvider(corpus: corpus),
            embedder: embedder,
            indexingBatchSize: 500,
            semanticCandidateLimit: 50_000
        )
        return AppDependencies(
            isLiveData: false,
            seed: dataset,
            conversationRepository: MockConversationRepository(dataset: dataset, delayNanoseconds: delayNanoseconds),
            messageRepository: MockMessageRepository(dataset: dataset, delayNanoseconds: delayNanoseconds),
            contactProvider: MockContactProvider(dataset: dataset, delayNanoseconds: delayNanoseconds),
            searchProvider: searchService,
            searchIndexer: searchService,
            permissionManager: MockPermissionManager(),
            messagingActions: nil,
            settingsStore: MockSettingsStore(),
            messageSender: MockMessageSender(delayNanoseconds: delayNanoseconds)
        )
    }

    static func test() -> AppDependencies {
        mock(delayNanoseconds: 0)
    }
}

struct MockAppDataset: Sendable {
    var currentUser: Contact
    var contacts: [Contact]
    var conversations: [Conversation]
    var messagesByConversation: [ConversationID: [Message]]

    var allMessages: [Message] {
        messagesByConversation.values.flatMap { $0 }.sorted { $0.sentAt < $1.sentAt }
    }

    static let rich: MockAppDataset = {
        let currentUser = MockData.currentUser
        let maya = MockData.contacts[1]
        let eli = MockData.contacts[2]
        let ava = MockData.contacts[3]
        let noah = contact(
            id: "contact.noah",
            name: "Noah Williams",
            value: "+1 (212) 555-0167",
            kind: .phoneNumber,
            service: .iMessage,
            initials: "NW",
            seed: "teal"
        )
        let priya = contact(
            id: "contact.priya",
            name: "Priya Shah",
            value: "priya@example.com",
            kind: .emailAddress,
            service: .iMessage,
            initials: "PS",
            seed: "rose"
        )
        let sam = contact(
            id: "contact.sam",
            name: "Sam Rivera",
            value: "+1 (503) 555-0128",
            kind: .phoneNumber,
            service: .sms,
            initials: "SR",
            seed: "indigo"
        )
        let lena = contact(
            id: "contact.lena",
            name: "Lena Ortiz",
            value: "lena@example.com",
            kind: .emailAddress,
            service: .iMessage,
            initials: "LO",
            seed: "copper"
        )
        let rowan = contact(
            id: "contact.rowan",
            name: "Rowan Kim",
            value: "+1 (650) 555-0194",
            kind: .phoneNumber,
            service: .iMessage,
            initials: "RK",
            seed: "blue"
        )
        let contacts = [currentUser, maya, eli, ava, noah, priya, sam, lena, rowan]

        var conversations: [Conversation] = []
        var messagesByConversation: [ConversationID: [Message]] = [:]

        func add(
            id rawID: String,
            title: String,
            participants: [Contact],
            kind: ConversationKind,
            service: MessageService,
            unreadCount: Int = 0,
            pinnedRank: Int? = nil,
            isMuted: Bool = false,
            isArchived: Bool = false,
            topic: String,
            count: Int,
            minutesBetween: Int,
            seedMessages: [Message] = []
        ) {
            let id = ConversationID(rawValue: rawID)
            let generated = transcript(
                conversationID: id,
                participants: participants,
                service: service,
                topic: topic,
                count: count,
                minutesBetween: minutesBetween
            )
            let messages = (generated + seedMessages).sorted { $0.sentAt < $1.sentAt }
            let last = messages.last
            let conversation = Conversation(
                id: id,
                title: title,
                participants: participants,
                kind: kind,
                service: service,
                unreadCount: unreadCount,
                pinnedRank: pinnedRank,
                isMuted: isMuted,
                isArchived: isArchived,
                lastMessage: last.map {
                    LastMessagePreview(
                        messageID: $0.id,
                        senderID: $0.senderID,
                        text: $0.body.plainText.isEmpty ? "Attachment" : $0.body.plainText,
                        sentAt: $0.sentAt,
                        hasAttachments: !$0.attachments.isEmpty
                    )
                },
                updatedAt: last?.sentAt ?? baseDate,
                lastReadMessageID: unreadCount == 0 ? last?.id : nil
            )
            conversations.append(conversation)
            messagesByConversation[id] = messages
        }

        add(
            id: "conversation.design-review",
            title: "Design review",
            participants: [maya, currentUser],
            kind: .direct,
            service: .iMessage,
            unreadCount: 2,
            pinnedRank: 0,
            topic: "search flow pagination transcript keyboard",
            count: 72,
            minutesBetween: 11,
            seedMessages: MockData.messages(for: "conversation.design-review")
        )
        add(
            id: "conversation.weekend",
            title: "Weekend plans",
            participants: [eli, ava, currentUser],
            kind: .group,
            service: .iMessage,
            pinnedRank: 1,
            topic: "coffee adapter printouts Saturday timing",
            count: 36,
            minutesBetween: 19,
            seedMessages: MockData.messages(for: "conversation.weekend")
        )
        add(
            id: "conversation.receipts",
            title: "Receipts",
            participants: [ava, currentUser],
            kind: .direct,
            service: .sms,
            isMuted: true,
            topic: "invoice receipt PDF reimbursement totals",
            count: 24,
            minutesBetween: 31,
            seedMessages: MockData.messages(for: "conversation.receipts")
        )
        add(
            id: "conversation.launch",
            title: "Launch room",
            participants: [maya, noah, priya, currentUser],
            kind: .group,
            service: .iMessage,
            unreadCount: 5,
            pinnedRank: 2,
            topic: "release checklist copy review screenshots notarization",
            count: 86,
            minutesBetween: 7
        )
        add(
            id: "conversation.search-indexing",
            title: "Search indexing",
            participants: [noah, currentUser],
            kind: .direct,
            service: .iMessage,
            unreadCount: 1,
            topic: "exact search semantic embeddings local index privacy",
            count: 94,
            minutesBetween: 9
        )
        add(
            id: "conversation.family",
            title: "Family",
            participants: [lena, rowan, currentUser],
            kind: .group,
            service: .iMessage,
            topic: "photos dinner calendar school pickup",
            count: 42,
            minutesBetween: 23
        )
        add(
            id: "conversation.sfo-trip",
            title: "SFO trip",
            participants: [sam, priya, currentUser],
            kind: .group,
            service: .sms,
            topic: "boarding pass terminal hotel confirmation flight",
            count: 28,
            minutesBetween: 37
        )
        add(
            id: "conversation.lena",
            title: "Lena Ortiz",
            participants: [lena, currentUser],
            kind: .direct,
            service: .iMessage,
            topic: "presentation notes rehearsal slides",
            count: 32,
            minutesBetween: 17
        )
        add(
            id: "conversation.rowan",
            title: "Rowan Kim",
            participants: [rowan, currentUser],
            kind: .direct,
            service: .iMessage,
            topic: "bike repair shop appointment",
            count: 16,
            minutesBetween: 52
        )
        add(
            id: "conversation.archive-import",
            title: "Archive import",
            participants: [noah, maya, currentUser],
            kind: .group,
            service: .iMessage,
            isArchived: true,
            topic: "old messages import archive attachment migration",
            count: 18,
            minutesBetween: 47
        )

        return MockAppDataset(
            currentUser: currentUser,
            contacts: contacts,
            conversations: conversations.sorted(by: Self.conversationSort),
            messagesByConversation: messagesByConversation
        )
    }()

    private static let baseDate = Date(timeIntervalSinceReferenceDate: 805_000_000)

    private static func contact(
        id: String,
        name: String,
        value: String,
        kind: ContactHandleKind,
        service: MessageService,
        initials: String,
        seed: String
    ) -> Contact {
        Contact(
            id: ContactID(rawValue: id),
            displayName: name,
            handles: [
                ContactHandle(
                    value: value,
                    normalizedValue: value.lowercased().filter { !$0.isWhitespace },
                    kind: kind,
                    service: service
                )
            ],
            avatar: ContactAvatar(initials: initials, colorSeed: seed),
            lastResolvedAt: baseDate
        )
    }

    private static func transcript(
        conversationID: ConversationID,
        participants: [Contact],
        service: MessageService,
        topic: String,
        count: Int,
        minutesBetween: Int
    ) -> [Message] {
        let senders = participants.filter { !$0.isCurrentUser }
        let topicWords = topic.split(separator: " ").map(String.init)
        let templates = [
            "Can you check the \(topicWords[safe: 0] ?? "thread") details before I send the next update?",
            "I found the older note about \(topicWords[safe: 1] ?? "the plan") and it still matches.",
            "The fast path should keep the transcript responsive even with years of history.",
            "Adding this here so exact search can find it later.",
            "This belongs in the local semantic index, not a cloud service.",
            "I will follow up after the preview finishes loading.",
            "The attachment is useful context for the conversation.",
            "Let's keep the wording short and make the status obvious."
        ]

        return (0..<count).map { index in
            let direction: MessageDirection = (index % 5 == 1 || index % 7 == 0) ? .outgoing : .incoming
            let sender = direction == .outgoing ? participants.first { $0.isCurrentUser } : senders[safe: index % max(senders.count, 1)]
            let minutesAgo = Double((count - index) * minutesBetween + 90)
            let attachment = attachmentIfNeeded(conversationID: conversationID, index: index)
            let reactions = reactionIfNeeded(sender: sender, index: index)
            let body = MessageBody.text(templates[index % templates.count])
            return Message(
                id: MessageID(rawValue: "\(conversationID.rawValue).generated.\(index)"),
                conversationID: conversationID,
                senderID: sender?.id,
                body: body,
                direction: direction,
                service: service,
                status: direction == .outgoing ? outgoingStatus(for: index) : .delivered,
                sentAt: baseDate.addingTimeInterval(-minutesAgo * 60),
                receivedAt: direction == .incoming ? baseDate.addingTimeInterval((-minutesAgo * 60) + 8) : nil,
                attachments: attachment.map { [$0] } ?? [],
                reactions: reactions,
                isEdited: index % 29 == 0 && index > 0
            )
        }
    }

    private static func attachmentIfNeeded(conversationID: ConversationID, index: Int) -> MessageAttachment? {
        guard index > 0, index % 11 == 0 || index % 17 == 0 else {
            return nil
        }

        if index % 17 == 0 {
            return MessageAttachment(
                id: AttachmentID(rawValue: "\(conversationID.rawValue).attachment.\(index).image"),
                kind: .image,
                filename: "Mock-Screenshot-\(index).png",
                uniformTypeIdentifier: "public.png",
                byteCount: 1_842_240,
                dimensions: AttachmentDimensions(width: 1800, height: 1200),
                transferState: index % 34 == 0 ? .remotePlaceholder : .local
            )
        }

        return MessageAttachment(
            id: AttachmentID(rawValue: "\(conversationID.rawValue).attachment.\(index).pdf"),
            kind: .file,
            filename: "Reference-\(index).pdf",
            uniformTypeIdentifier: "com.adobe.pdf",
            byteCount: 418_600,
            transferState: index % 22 == 0 ? .downloading : .local
        )
    }

    private static func reactionIfNeeded(sender: Contact?, index: Int) -> [MessageReaction] {
        guard let sender, index > 0, index % 8 == 0 else {
            return []
        }

        return [
            MessageReaction(
                id: "reaction.\(sender.id.rawValue).\(index)",
                kind: index % 16 == 0 ? .loved : .liked,
                senderID: sender.id,
                createdAt: baseDate.addingTimeInterval(Double(index) * 7),
                displayText: index % 16 == 0 ? "Loved" : "Liked"
            )
        ]
    }

    private static func outgoingStatus(for index: Int) -> MessageDeliveryStatus {
        if index % 53 == 0 {
            return .failed
        }
        if index % 31 == 0 {
            return .sending
        }
        if index % 3 == 0 {
            return .read
        }
        return .delivered
    }

    static func conversationSort(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        switch (lhs.pinnedRank, rhs.pinnedRank) {
        case let (left?, right?):
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

private struct MockConversationRepository: ConversationRepository {
    let dataset: MockAppDataset
    let delayNanoseconds: UInt64

    func conversations(page: PageRequest, filter: ConversationFilter) async throws -> Page<Conversation> {
        await delay()
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = dataset.conversations
            .filter { filter.includeArchived || !$0.isArchived }
            .filter { !filter.unreadOnly || $0.unreadCount > 0 }
            .filter { !filter.pinnedOnly || $0.pinnedRank != nil }
            .filter { conversation in
                guard !query.isEmpty else {
                    return true
                }
                return conversation.matches(query: query)
                    || dataset.messagesByConversation[conversation.id, default: []].contains { $0.body.plainText.localizedCaseInsensitiveContains(query) }
            }
            .sorted(by: MockAppDataset.conversationSort)
        return pageItems(filtered, request: page)
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        await delay()
        guard let conversation = dataset.conversations.first(where: { $0.id == id }) else {
            throw I2MessageError.notFound(resource: "Conversation", id: id.rawValue)
        }
        return conversation
    }

    func observeConversations(filter: ConversationFilter) -> AsyncThrowingStream<[Conversation], Error> {
        AsyncThrowingStream { continuation in
            Task {
                let page = try await conversations(page: PageRequest(limit: 200), filter: filter)
                continuation.yield(page.items)
                continuation.finish()
            }
        }
    }

    private func delay() async {
        guard delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

private struct MockMessageRepository: MessageRepository {
    let dataset: MockAppDataset
    let delayNanoseconds: UInt64

    func messages(
        in conversationID: ConversationID,
        page: PageRequest,
        around anchor: MessageID?
    ) async throws -> Page<Message> {
        await delay()
        let messages = dataset.messagesByConversation[conversationID, default: []].sorted { $0.sentAt < $1.sentAt }

        if let anchor, let index = messages.firstIndex(where: { $0.id == anchor }) {
            let half = max(page.limit / 2, 1)
            let start = max(index - half, 0)
            let end = min(index + half + 1, messages.count)
            return Page(
                items: Array(messages[start..<end]),
                nextCursor: start > 0 ? PageCursor(rawValue: "older:\(start)") : nil,
                previousCursor: end < messages.count ? PageCursor(rawValue: "newer:\(end)") : nil,
                hasMore: start > 0 || end < messages.count,
                totalCount: messages.count
            )
        }

        let endExclusive = page.cursor.flatMap { cursorValue($0, prefix: "older") } ?? messages.count
        let start = max(0, endExclusive - page.limit)
        let items = start < endExclusive ? Array(messages[start..<endExclusive]) : []
        return Page(
            items: items,
            nextCursor: start > 0 ? PageCursor(rawValue: "older:\(start)") : nil,
            previousCursor: endExclusive < messages.count ? PageCursor(rawValue: "newer:\(endExclusive)") : nil,
            hasMore: start > 0,
            totalCount: messages.count
        )
    }

    func message(id: MessageID) async throws -> Message {
        await delay()
        guard let message = dataset.allMessages.first(where: { $0.id == id }) else {
            throw I2MessageError.notFound(resource: "Message", id: id.rawValue)
        }
        return message
    }

    func observeMessages(in conversationID: ConversationID) -> AsyncThrowingStream<[Message], Error> {
        AsyncThrowingStream { continuation in
            Task {
                let page = try await messages(in: conversationID, page: PageRequest(limit: 80), around: nil)
                continuation.yield(page.items)
                continuation.finish()
            }
        }
    }

    private func delay() async {
        guard delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

private struct MockContactProvider: ContactProviding {
    let dataset: MockAppDataset
    let delayNanoseconds: UInt64

    func contacts(matching query: String, page: PageRequest) async throws -> Page<Contact> {
        await delay()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = dataset.contacts
            .filter { !$0.isCurrentUser }
            .filter { contact in
                guard !trimmed.isEmpty else { return true }
                return contact.displayName.localizedCaseInsensitiveContains(trimmed)
                    || contact.handles.contains { $0.value.localizedCaseInsensitiveContains(trimmed) }
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return pageItems(filtered, request: page)
    }

    func contact(id: ContactID) async throws -> Contact {
        await delay()
        guard let contact = dataset.contacts.first(where: { $0.id == id }) else {
            throw I2MessageError.notFound(resource: "Contact", id: id.rawValue)
        }
        return contact
    }

    private func delay() async {
        guard delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

private struct MockSearchProvider: SearchProviding {
    let dataset: MockAppDataset
    let delayNanoseconds: UInt64

    func exactSearch(_ query: ExactSearchQuery, page: PageRequest) async throws -> Page<SearchResult> {
        await delay()
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return Page(items: [], hasMore: false, totalCount: 0)
        }

        var results: [SearchResult] = []
        for conversation in dataset.conversations where query.conversationID == nil || query.conversationID == conversation.id {
            if conversation.matches(query: text) {
                results.append(
                    SearchResult(
                        id: "conversation.\(conversation.id.rawValue)",
                        kind: .conversation,
                        conversationID: conversation.id,
                        title: conversation.title,
                        subtitle: "Conversation",
                        snippet: conversation.lastMessage?.text ?? "No preview available",
                        matchedRanges: ranges(in: conversation.title, matching: text),
                        score: 0.96,
                        date: conversation.updatedAt
                    )
                )
            }

            for message in dataset.messagesByConversation[conversation.id, default: []] {
                guard query.senderID == nil || query.senderID == message.senderID else { continue }
                guard query.sentAfter == nil || message.sentAt >= query.sentAfter! else { continue }
                guard query.sentBefore == nil || message.sentAt <= query.sentBefore! else { continue }

                if message.body.plainText.localizedCaseInsensitiveContains(text) {
                    results.append(
                        SearchResult(
                            id: "message.\(message.id.rawValue)",
                            kind: .message,
                            conversationID: conversation.id,
                            messageID: message.id,
                            contactID: message.senderID,
                            title: conversation.title,
                            subtitle: senderName(for: message.senderID),
                            snippet: snippet(from: message.body.plainText, matching: text),
                            matchedRanges: ranges(in: message.body.plainText, matching: text),
                            score: 1,
                            date: message.sentAt
                        )
                    )
                }

                guard query.includeAttachments else { continue }
                for attachment in message.attachments where attachment.filename.localizedCaseInsensitiveContains(text) {
                    results.append(
                        SearchResult(
                            id: "attachment.\(attachment.id.rawValue)",
                            kind: .attachment,
                            conversationID: conversation.id,
                            messageID: message.id,
                            attachmentID: attachment.id,
                            title: attachment.filename,
                            subtitle: conversation.title,
                            snippet: "\(attachment.kind.rawValue.capitalized) attachment",
                            matchedRanges: ranges(in: attachment.filename, matching: text),
                            score: 0.91,
                            date: message.sentAt
                        )
                    )
                }
            }
        }

        for contact in dataset.contacts where contact.matches(query: text) {
            results.append(
                SearchResult(
                    id: "contact.\(contact.id.rawValue)",
                    kind: .contact,
                    contactID: contact.id,
                    title: contact.displayName,
                    subtitle: "Contact",
                    snippet: contact.handles.first?.value ?? "No handle",
                    matchedRanges: ranges(in: contact.displayName, matching: text),
                    score: 0.94,
                    date: contact.lastResolvedAt
                )
            )
        }

        let sorted = results.sorted {
            if $0.score == $1.score {
                return ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            }
            return $0.score > $1.score
        }
        return pageItems(sorted, request: page)
    }

    func semanticSearch(_ query: SemanticSearchQuery) async throws -> [SemanticSnippet] {
        await delay()
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return []
        }

        let queryTokens = Set(tokens(in: text))
        let snippets = dataset.conversations.flatMap { conversation -> [SemanticSnippet] in
            guard query.conversationID == nil || query.conversationID == conversation.id else {
                return []
            }
            let messages = dataset.messagesByConversation[conversation.id, default: []]
            return stride(from: 0, to: messages.count, by: 6).compactMap { index in
                let window = Array(messages[index..<min(index + 6, messages.count)])
                let combined = window.map { $0.body.plainText }.joined(separator: " ")
                let overlap = Set(tokens(in: combined)).intersection(queryTokens).count
                let similarity = min(0.98, 0.67 + Double(overlap) * 0.075 + recencyBoost(for: window.last?.sentAt))
                guard similarity >= query.minimumSimilarity || overlap > 0 else {
                    return nil
                }
                return SemanticSnippet(
                    id: "semantic.\(conversation.id.rawValue).\(index)",
                    conversationID: conversation.id,
                    sourceMessageIDs: window.map(\.id),
                    text: snippet(from: combined, matching: text, limit: 220),
                    similarity: similarity,
                    embeddingModelIdentifier: "local-mock-miniLM",
                    generatedAt: Date(timeIntervalSinceReferenceDate: 805_010_000)
                )
            }
        }
        .sorted { $0.similarity > $1.similarity }

        return Array(snippets.prefix(query.limit))
    }

    private func senderName(for id: ContactID?) -> String {
        guard let id else { return "System" }
        return dataset.contacts.first { $0.id == id }?.displayName ?? "Unknown"
    }

    private func delay() async {
        guard delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

private struct MockSearchIndexer: SearchIndexing {
    let delayNanoseconds: UInt64

    func rebuildExactIndex(progress: @Sendable @escaping (Double) -> Void) async throws {
        try await rebuild(progress: progress)
    }

    func rebuildSemanticIndex(progress: @Sendable @escaping (Double) -> Void) async throws {
        try await rebuild(progress: progress)
    }

    func invalidateIndex(for conversationID: ConversationID?) async throws {}

    private func rebuild(progress: @Sendable @escaping (Double) -> Void) async throws {
        for step in 0...8 {
            progress(Double(step) / 8)
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds / 2)
            }
        }
    }
}

private actor MockPermissionManager: PermissionManaging {
    private var snapshot = PermissionSnapshot(
        statuses: [
            PermissionStatus(
                permission: .fullDiskAccess,
                state: .notDetermined,
                reason: "Required for read-only Messages history access.",
                lastCheckedAt: Date(timeIntervalSinceReferenceDate: 805_000_000)
            ),
            PermissionStatus(
                permission: .contacts,
                state: .granted,
                reason: "Mock contacts are available.",
                lastCheckedAt: Date(timeIntervalSinceReferenceDate: 805_000_000)
            ),
            PermissionStatus(
                permission: .appleEventsMessages,
                state: .notDetermined,
                reason: "Required for supported send automation.",
                lastCheckedAt: Date(timeIntervalSinceReferenceDate: 805_000_000)
            ),
            PermissionStatus(
                permission: .notifications,
                state: .denied,
                reason: "Notifications are off in mock mode.",
                lastCheckedAt: Date(timeIntervalSinceReferenceDate: 805_000_000)
            )
        ]
    )

    func permissionSnapshot() async -> PermissionSnapshot {
        snapshot
    }

    func request(_ permission: AppPermission) async throws -> PermissionStatus {
        let status = PermissionStatus(
            permission: permission,
            state: permission == .notifications ? .denied : .granted,
            reason: permission == .notifications ? "Enable notifications in System Settings." : "Granted in mock mode.",
            lastCheckedAt: Date()
        )
        snapshot.statuses.removeAll { $0.permission == permission }
        snapshot.statuses.append(status)
        snapshot.statuses.sort { $0.permission.rawValue < $1.permission.rawValue }
        return status
    }

    func openSystemSettings(for permission: AppPermission) async {}
}

private actor MockSettingsStore: SettingsStoring {
    private var settings = AppSettings(
        theme: .system,
        transcriptDensity: .comfortable,
        pageSize: 42,
        launchAtLogin: false,
        search: SearchIndexSettings(
            exactIndexEnabled: true,
            semanticIndexEnabled: true,
            semanticModelIdentifier: "local-mock-miniLM",
            indexAttachments: true
        ),
        privacy: PrivacySettings(
            allowExternalEmbeddingProviders: false,
            redactLogs: true
        )
    )

    func loadSettings() async throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) async throws {
        self.settings = settings
    }
}

private struct MockMessageSender: MessageSending {
    let delayNanoseconds: UInt64

    func validate(_ draft: MessageDraft) async throws -> SendOperation {
        let hasText = !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText || !draft.attachments.isEmpty else {
            throw I2MessageError.validationFailed(field: "message", reason: "Type a message or attach a file.")
        }

        return SendOperation(
            id: "send.\(UUID().uuidString)",
            draft: draft,
            state: .validating,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func send(_ draft: MessageDraft) async throws -> SendReceipt {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let operation = try await validate(draft)
        let conversationID: ConversationID?
        switch draft.target {
        case .existingConversation(let id):
            conversationID = id
        case .handles:
            conversationID = nil
        }
        return SendReceipt(
            operationID: operation.id,
            conversationID: conversationID,
            messageID: MessageID(rawValue: "mock.sent.\(UUID().uuidString)"),
            sentAt: Date()
        )
    }
}

private func pageItems<Element: Sendable>(_ items: [Element], request: PageRequest) -> Page<Element> {
    let offset = request.cursor.flatMap { cursorValue($0, prefix: "offset") } ?? 0
    let start = min(max(offset, 0), items.count)
    let end = min(start + max(request.limit, 1), items.count)
    let pageItems = start < end ? Array(items[start..<end]) : []
    return Page(
        items: pageItems,
        nextCursor: end < items.count ? PageCursor(rawValue: "offset:\(end)") : nil,
        previousCursor: start > 0 ? PageCursor(rawValue: "offset:\(max(start - request.limit, 0))") : nil,
        hasMore: end < items.count,
        totalCount: items.count
    )
}

private func cursorValue(_ cursor: PageCursor, prefix: String) -> Int? {
    let parts = cursor.rawValue.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, parts[0] == prefix else {
        return nil
    }
    return Int(parts[1])
}

private func ranges(in text: String, matching query: String) -> [i2MessageCore.TextRange] {
    let loweredText = text.lowercased()
    let loweredQuery = query.lowercased()
    guard !loweredQuery.isEmpty, let range = loweredText.range(of: loweredQuery) else {
        return []
    }
    let location = loweredText.distance(from: loweredText.startIndex, to: range.lowerBound)
    return [i2MessageCore.TextRange(location: location, length: loweredQuery.count)]
}

private func snippet(from text: String, matching query: String, limit: Int = 160) -> String {
    guard text.count > limit else {
        return text
    }

    let lowered = text.lowercased()
    let loweredQuery = query.lowercased()
    guard let range = lowered.range(of: loweredQuery) else {
        return String(text.prefix(limit)) + "..."
    }

    let queryStart = lowered.distance(from: lowered.startIndex, to: range.lowerBound)
    let start = max(queryStart - 56, 0)
    let end = min(start + limit, text.count)
    let startIndex = text.index(text.startIndex, offsetBy: start)
    let endIndex = text.index(text.startIndex, offsetBy: end)
    let prefix = start > 0 ? "..." : ""
    let suffix = end < text.count ? "..." : ""
    return prefix + String(text[startIndex..<endIndex]) + suffix
}

private func tokens(in text: String) -> [String] {
    text.lowercased()
        .split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
        .filter { $0.count > 2 }
}

private func recencyBoost(for date: Date?) -> Double {
    guard let date else { return 0 }
    let age = abs(date.timeIntervalSince(Date(timeIntervalSinceReferenceDate: 805_000_000)))
    return max(0, 0.08 - min(age / 900_000, 0.08))
}

private extension Conversation {
    func matches(query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || participants.contains { $0.displayName.localizedCaseInsensitiveContains(query) }
            || (lastMessage?.text.localizedCaseInsensitiveContains(query) ?? false)
    }
}

private extension Contact {
    func matches(query: String) -> Bool {
        displayName.localizedCaseInsensitiveContains(query)
            || handles.contains { $0.value.localizedCaseInsensitiveContains(query) || $0.normalizedValue.localizedCaseInsensitiveContains(query) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard !isEmpty, indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
