import XCTest
@testable import i2Message
import i2MessageCore

@MainActor
final class AppIntegrationPerformanceTests: XCTestCase {
    func testIndexedFixtureCoversSearchRoutingPagingAndSend() async throws {
        let dataset = Self.syntheticDataset(conversationCount: 32, messagesPerConversation: 90)
        let dependencies = AppDependencies.indexedFixture(dataset: dataset, indexURL: Self.temporaryIndexURL())
        try await dependencies.searchIndexer.rebuildExactIndex { _ in }
        try await dependencies.searchIndexer.rebuildSemanticIndex { _ in }

        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()

        XCTAssertFalse(model.filteredConversations.isEmpty)
        XCTAssertFalse(model.selectedMessages.isEmpty)

        let initialCount = model.selectedMessages.count
        await model.loadOlderMessages()
        XCTAssertGreaterThan(model.selectedMessages.count, initialCount)

        model.sidebarDestination = .search
        model.searchMode = .exact
        model.searchQuery = "needle exact phrase"
        await model.performSearch(reset: true)

        XCTAssertEqual(model.searchPhase, .loaded)
        let messageResult = try XCTUnwrap(model.exactSearchResults.first { $0.messageID != nil })
        await model.openSearchResult(messageResult)

        XCTAssertEqual(model.sidebarDestination, .conversations)
        XCTAssertEqual(model.selectedConversationID, messageResult.conversationID)
        XCTAssertEqual(model.highlightedMessageID, messageResult.messageID)
        XCTAssertTrue(model.selectedMessages.contains { $0.id == messageResult.messageID })

        model.searchMode = .semantic
        model.searchQuery = "fast search lookup"
        await model.performSearch(reset: true)

        XCTAssertEqual(model.searchPhase, .loaded)
        XCTAssertFalse(model.semanticSnippets.isEmpty)

        model.updateDraftText("Integration test send")
        let beforeSendCount = model.selectedMessages.count
        await model.sendCurrentDraft()

        XCTAssertEqual(model.currentDraftText, "")
        XCTAssertGreaterThan(model.selectedMessages.count, beforeSendCount)
        XCTAssertEqual(model.statusBanner?.tone, .success)
    }

    func testSyntheticPerformanceBudgets() async throws {
        let dataset = Self.syntheticDataset(conversationCount: 120, messagesPerConversation: 100)

        let launchDependencies = AppDependencies.fixture(dataset: dataset, delayNanoseconds: 0)
        let launchModel = AppViewModel(dependencies: launchDependencies)
        let launch = await Self.measureSeconds {
            await launchModel.load()
        }
        XCTAssertLessThan(launch, 0.75, "Fixture launch should stay visibly instant.")

        let paging = await Self.measureSeconds {
            await launchModel.loadOlderMessages()
        }
        XCTAssertLessThan(paging, 0.15, "Transcript paging should remain bounded.")

        let indexedDependencies = AppDependencies.indexedFixture(dataset: dataset, indexURL: Self.temporaryIndexURL())
        try await indexedDependencies.searchIndexer.rebuildExactIndex { _ in }
        try await indexedDependencies.searchIndexer.rebuildSemanticIndex { _ in }
        let indexedModel = AppViewModel(dependencies: indexedDependencies)
        await indexedModel.refreshEverything()

        indexedModel.searchMode = .exact
        indexedModel.searchQuery = "needle exact phrase"
        let exactSearch = await Self.measureSeconds {
            await indexedModel.performSearch(reset: true)
        }
        XCTAssertLessThan(exactSearch, 0.25, "Exact search first page should be sub-interaction latency.")
        XCTAssertFalse(indexedModel.exactSearchResults.isEmpty)

        indexedModel.searchMode = .semantic
        indexedModel.searchQuery = "fast search lookup"
        let semanticSearch = await Self.measureSeconds {
            await indexedModel.performSearch(reset: true)
        }
        XCTAssertLessThan(semanticSearch, 1.0, "Semantic search should return first usable local results quickly.")
        XCTAssertFalse(indexedModel.semanticSnippets.isEmpty)

        indexedModel.searchMode = .exact
        indexedModel.searchQuery = "needle exact phrase"
        await indexedModel.performSearch(reset: true)
        let result = try XCTUnwrap(indexedModel.exactSearchResults.first { $0.messageID != nil })
        let transcriptRoute = await Self.measureSeconds {
            await indexedModel.openSearchResult(result)
        }
        XCTAssertLessThan(transcriptRoute, 0.25, "Search result transcript routing should load the anchor page quickly.")
        XCTAssertTrue(indexedModel.selectedMessages.contains { $0.id == result.messageID })

        try Self.writePerformanceReport(
            [
                "dataset.conversations": Double(dataset.conversations.count),
                "dataset.messages": Double(dataset.allMessages.count),
                "launch.seconds": launch,
                "conversationPaging.seconds": paging,
                "exactSearchFirstPage.seconds": exactSearch,
                "semanticSearchFirstResults.seconds": semanticSearch,
                "transcriptRoute.seconds": transcriptRoute
            ]
        )
    }

    private static func syntheticDataset(conversationCount: Int, messagesPerConversation: Int) -> MockAppDataset {
        let baseDate = Date(timeIntervalSinceReferenceDate: 812_000_000)
        let currentUser = contact(
            id: "contact.current",
            name: "You",
            value: "you@example.com",
            isCurrentUser: true,
            baseDate: baseDate
        )
        let contacts = (0..<12).map { index in
            contact(
                id: "contact.synthetic.\(index)",
                name: "Fixture Contact \(index)",
                value: "fixture\(index)@example.com",
                isCurrentUser: false,
                baseDate: baseDate
            )
        }

        var conversations: [Conversation] = []
        var messagesByConversation: [ConversationID: [Message]] = [:]

        for conversationIndex in 0..<conversationCount {
            let participant = contacts[conversationIndex % contacts.count]
            let conversationID = ConversationID(rawValue: "conversation.synthetic.\(conversationIndex)")
            let messages = (0..<messagesPerConversation).map { messageIndex in
                message(
                    conversationID: conversationID,
                    sender: messageIndex.isMultiple(of: 3) ? currentUser : participant,
                    service: conversationIndex.isMultiple(of: 5) ? .sms : .iMessage,
                    index: messageIndex,
                    globalIndex: conversationIndex * messagesPerConversation + messageIndex,
                    baseDate: baseDate
                )
            }
            let last = messages.last
            conversations.append(
                Conversation(
                    id: conversationID,
                    title: "Synthetic Thread \(conversationIndex)",
                    participants: [participant, currentUser],
                    kind: .direct,
                    service: conversationIndex.isMultiple(of: 5) ? .sms : .iMessage,
                    unreadCount: conversationIndex.isMultiple(of: 9) ? 2 : 0,
                    pinnedRank: conversationIndex < 3 ? conversationIndex : nil,
                    lastMessage: last.map {
                        LastMessagePreview(
                            messageID: $0.id,
                            senderID: $0.senderID,
                            text: $0.body.plainText,
                            sentAt: $0.sentAt,
                            hasAttachments: !$0.attachments.isEmpty
                        )
                    },
                    updatedAt: last?.sentAt ?? baseDate
                )
            )
            messagesByConversation[conversationID] = messages
        }

        return MockAppDataset(
            currentUser: currentUser,
            contacts: [currentUser] + contacts,
            conversations: conversations.sorted(by: MockAppDataset.conversationSort),
            messagesByConversation: messagesByConversation
        )
    }

    private static func contact(
        id: String,
        name: String,
        value: String,
        isCurrentUser: Bool,
        baseDate: Date
    ) -> Contact {
        Contact(
            id: ContactID(rawValue: id),
            displayName: name,
            handles: [
                ContactHandle(
                    value: value,
                    normalizedValue: value.lowercased(),
                    kind: .emailAddress,
                    service: .iMessage
                )
            ],
            avatar: ContactAvatar(initials: initials(for: name), colorSeed: id),
            isCurrentUser: isCurrentUser,
            lastResolvedAt: baseDate
        )
    }

    private static func message(
        conversationID: ConversationID,
        sender: Contact,
        service: MessageService,
        index: Int,
        globalIndex: Int,
        baseDate: Date
    ) -> Message {
        let hasNeedle = globalIndex.isMultiple(of: 37)
        let text = hasNeedle
            ? "Needle exact phrase \(globalIndex) with fast search lookup context and private local indexing."
            : "Synthetic transcript line \(globalIndex) keeps pagination realistic without private user data."

        return Message(
            id: MessageID(rawValue: "message.synthetic.\(globalIndex)"),
            conversationID: conversationID,
            senderID: sender.id,
            body: .text(text),
            direction: sender.isCurrentUser ? .outgoing : .incoming,
            service: service,
            status: sender.isCurrentUser ? .sent : .delivered,
            sentAt: baseDate.addingTimeInterval(Double(globalIndex) * 15),
            attachments: index.isMultiple(of: 41) ? [
                MessageAttachment(
                    id: AttachmentID(rawValue: "attachment.synthetic.\(globalIndex)"),
                    messageID: MessageID(rawValue: "message.synthetic.\(globalIndex)"),
                    kind: .file,
                    filename: "Fixture-\(globalIndex).pdf",
                    uniformTypeIdentifier: "com.adobe.pdf",
                    byteCount: 128_000
                )
            ] : []
        )
    }

    private static func initials(for name: String) -> String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private static func temporaryIndexURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("i2message-app-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("index.sqlite")
    }

    private static func measureSeconds(_ operation: () async throws -> Void) async rethrows -> TimeInterval {
        let start = Date()
        try await operation()
        return Date().timeIntervalSince(start)
    }

    private static func format(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
    }

    private static func writePerformanceReport(_ metrics: [String: Double]) throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
        let root = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("build/performance", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let ordered = metrics.keys.sorted().reduce(into: [String: Double]()) { result, key in
            result[key] = metrics[key]
        }
        let data = try JSONSerialization.data(withJSONObject: ordered, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("app-synthetic-results.json"), options: .atomic)
    }
}
