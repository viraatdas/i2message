import XCTest
@testable import i2MessageCore

/// Covers the streaming, uncapped corpus ingestion added for full-history
/// search: every conversation and message is indexed, unchanged conversations
/// are skipped on later passes, and the semantic index stays bounded to the
/// most recent documents.
final class SearchCorpusStreamingTests: XCTestCase {
    func testExactRebuildIndexesEveryConversationAndMessageWithoutCaps() async throws {
        // 24 conversations / 2,000 messages — well past the old
        // 10-conversation × 500-message production caps.
        let corpus = SearchTestFixtures.largeCorpus(messageCount: 2_000, needleEvery: 100)
        let service = SearchTestFixtures.service(corpus: corpus, batchSize: 128)

        try await service.rebuildExactIndex { _ in }

        let state = try await service.localIndexState()
        XCTAssertEqual(
            state.documentCount,
            corpus.conversations.count + corpus.contacts.count + corpus.messages.count
        )
        let messageDocumentCount = try await service.indexedDocumentCount(kind: .message)
        XCTAssertEqual(messageDocumentCount, corpus.messages.count)

        // The oldest message in the corpus must be findable.
        let oldest = try XCTUnwrap(corpus.messages.min { $0.sentAt < $1.sentAt })
        let page = try await service.exactSearch(
            ExactSearchQuery(text: oldest.body.plainText, conversationID: oldest.conversationID),
            page: PageRequest(limit: 50)
        )
        XCTAssertTrue(page.items.contains { $0.messageID == oldest.id })
    }

    func testIncrementalRebuildStreamsOnlyChangedConversations() async throws {
        let provider = RecordingCorpusProvider(corpus: SearchTestFixtures.focusedCorpus())
        let service = LocalSearchService(
            indexURL: Self.temporaryIndexURL(),
            corpusProvider: provider,
            embedder: HashingSemanticEmbedder(dimension: 96),
            indexingBatchSize: 100,
            semanticCandidateLimit: 50_000
        )

        try await service.rebuildExactIndex { _ in }
        try await service.rebuildSemanticIndex { _ in }
        XCTAssertEqual(Set(provider.streamedConversationIDs).count, 3)
        let indexed = try await service.localIndexState()
        XCTAssertGreaterThan(indexed.semanticEmbeddingCount, 0)

        // Nothing changed: the rebuild must not stream any message history and
        // must leave all semantic embeddings untouched.
        provider.resetRecording()
        try await service.rebuildExactIndex { _ in }
        XCTAssertTrue(provider.streamedConversationIDs.isEmpty)
        let afterNoOp = try await service.localIndexState()
        XCTAssertEqual(afterNoOp.semanticEmbeddingCount, indexed.semanticEmbeddingCount)

        // A new message in one conversation re-streams that conversation only.
        let lunchID: ConversationID = "conversation.lunch"
        let newMessage = Message(
            id: "message.lunch.2",
            conversationID: lunchID,
            senderID: SearchTestFixtures.maya.id,
            body: .text("Rooftop zanzibar tapas afterwards?"),
            direction: .incoming,
            service: .iMessage,
            status: .delivered,
            sentAt: SearchTestFixtures.baseDate.addingTimeInterval(-30)
        )
        provider.append(newMessage, to: lunchID)
        provider.resetRecording()

        try await service.rebuildExactIndex { _ in }
        XCTAssertEqual(provider.streamedConversationIDs, [lunchID])

        let page = try await service.exactSearch(
            ExactSearchQuery(text: "zanzibar"),
            page: PageRequest(limit: 5)
        )
        XCTAssertEqual(page.items.first?.messageID, newMessage.id)
    }

    func testInterruptedRebuildResumesWithoutRestreamingFinishedConversations() async throws {
        let provider = RecordingCorpusProvider(corpus: SearchTestFixtures.focusedCorpus())
        let service = LocalSearchService(
            indexURL: Self.temporaryIndexURL(),
            corpusProvider: provider,
            embedder: HashingSemanticEmbedder(dimension: 96),
            indexingBatchSize: 100,
            semanticCandidateLimit: 50_000
        )

        // Cancellation surfaces while the second conversation streams. The
        // first conversation finished, so its signature is recorded and the
        // follow-up pass only streams the two conversations the interrupted
        // pass never completed.
        provider.cancelOnStreamNumber = 2
        do {
            try await service.rebuildExactIndex { _ in }
            XCTFail("Expected the rebuild to be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(provider.streamedConversationIDs.count, 2)
        let finishedConversation = provider.streamedConversationIDs[0]

        provider.cancelOnStreamNumber = nil
        provider.resetRecording()
        try await service.rebuildExactIndex { _ in }
        XCTAssertFalse(provider.streamedConversationIDs.contains(finishedConversation))
        XCTAssertEqual(provider.streamedConversationIDs.count, 2)
    }

    func testSemanticIndexIsBoundedToMostRecentDocuments() async throws {
        let corpus = SearchTestFixtures.largeCorpus(messageCount: 400, needleEvery: 50)
        let budget = 150
        let service = LocalSearchService(
            indexURL: Self.temporaryIndexURL(),
            corpusProvider: StaticSearchIndexCorpusProvider(corpus: corpus),
            embedder: HashingSemanticEmbedder(dimension: 64),
            indexingBatchSize: 100,
            semanticCandidateLimit: budget
        )

        try await service.rebuildExactIndex { _ in }
        try await service.rebuildSemanticIndex { _ in }

        let state = try await service.localIndexState()
        XCTAssertGreaterThan(state.documentCount, budget)
        XCTAssertEqual(state.semanticEmbeddingCount, budget)
        XCTAssertEqual(state.pendingSemanticEmbeddingCount, 0)
    }

    private static func temporaryIndexURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("i2message-streaming-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("index.sqlite")
    }
}

/// Static corpus provider that records which conversations had their message
/// history streamed, so tests can assert the incremental-skip behavior.
private final class RecordingCorpusProvider: SearchIndexCorpusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var corpus: SearchIndexCorpus
    private var streamed: [ConversationID] = []
    var cancelOnStreamNumber: Int?

    init(corpus: SearchIndexCorpus) {
        self.corpus = corpus
    }

    var streamedConversationIDs: [ConversationID] {
        lock.lock()
        defer { lock.unlock() }
        return streamed
    }

    func resetRecording() {
        lock.lock()
        streamed = []
        lock.unlock()
    }

    func append(_ message: Message, to conversationID: ConversationID) {
        lock.lock()
        defer { lock.unlock() }
        corpus.messages.append(message)
        if let index = corpus.conversations.firstIndex(where: { $0.id == conversationID }) {
            corpus.conversations[index].updatedAt = message.sentAt
            corpus.conversations[index].lastMessage = LastMessagePreview(
                messageID: message.id,
                senderID: message.senderID,
                text: message.body.plainText,
                sentAt: message.sentAt,
                hasAttachments: false
            )
        }
    }

    func searchIndexCorpus() async throws -> SearchIndexCorpus {
        currentCorpus()
    }

    private func currentCorpus() -> SearchIndexCorpus {
        lock.lock()
        defer { lock.unlock() }
        return corpus
    }

    func messageBatches(in conversationID: ConversationID, batchSize: Int) -> AsyncThrowingStream<[Message], Error> {
        lock.lock()
        streamed.append(conversationID)
        let messages = corpus.messages.filter { $0.conversationID == conversationID }
        let shouldCancel = cancelOnStreamNumber == streamed.count
        lock.unlock()

        return AsyncThrowingStream { continuation in
            if shouldCancel {
                // Simulates the app quitting mid-build: cancellation surfaces
                // while this conversation's history is being streamed.
                continuation.finish(throwing: CancellationError())
            } else {
                continuation.yield(messages)
                continuation.finish()
            }
        }
    }
}
