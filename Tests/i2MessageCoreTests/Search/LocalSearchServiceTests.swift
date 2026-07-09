import XCTest
@testable import i2MessageCore

final class LocalSearchServiceTests: XCTestCase {
    func testTokenizerNormalizesCaseDiacriticsAndPunctuation() {
        let tokens = SearchTokenizer.uniqueTokenValues(in: "Café-lunch, FAST search!!")

        XCTAssertEqual(tokens, ["cafe", "lunch", "fast", "search"])
    }

    func testExactSearchRanksFiltersHighlightsAndPaginates() async throws {
        let service = SearchTestFixtures.service(corpus: SearchTestFixtures.focusedCorpus(), batchSize: 2)
        let progress = ProgressRecorder()
        try await service.rebuildExactIndex { progress.record($0) }

        XCTAssertEqual(progress.last, 1)

        let firstPage = try await service.exactSearch(
            ExactSearchQuery(text: "adapter", conversationID: "conversation.design"),
            page: PageRequest(limit: 2)
        )

        XCTAssertEqual(firstPage.items.count, 2)
        XCTAssertTrue(firstPage.hasMore)
        XCTAssertNotNil(firstPage.nextCursor)
        XCTAssertEqual(firstPage.items.first?.messageID, "message.design.3")
        XCTAssertFalse(firstPage.items.first?.matchedRanges.isEmpty ?? true)

        let secondPage = try await service.exactSearch(
            ExactSearchQuery(text: "adapter", conversationID: "conversation.design"),
            page: PageRequest(cursor: try XCTUnwrap(firstPage.nextCursor), limit: 2)
        )

        XCTAssertFalse(secondPage.items.map(\.id).contains(firstPage.items[0].id))
        XCTAssertEqual(secondPage.totalCount, firstPage.totalCount)

        let mayaOnly = try await service.exactSearch(
            ExactSearchQuery(text: "adapter", senderID: "contact.maya"),
            page: PageRequest(limit: 10)
        )
        XCTAssertTrue(mayaOnly.items.allSatisfy { $0.contactID == "contact.maya" || $0.kind == .conversation })

        let withoutAttachments = try await service.exactSearch(
            ExactSearchQuery(text: "invoice", includeAttachments: false),
            page: PageRequest(limit: 10)
        )
        XCTAssertFalse(withoutAttachments.items.contains { $0.kind == .attachment })

        let withAttachments = try await service.exactSearch(
            ExactSearchQuery(text: "invoice", includeAttachments: true),
            page: PageRequest(limit: 10)
        )
        XCTAssertTrue(withAttachments.items.contains { $0.kind == .attachment })

        let smsOnly = try await service.exactSearch(
            text: "invoice",
            filters: LocalSearchFilters(service: .sms),
            page: PageRequest(limit: 10)
        )
        XCTAssertTrue(smsOnly.items.allSatisfy { $0.conversationID == "conversation.receipts" })
    }

    func testTypeaheadRecentSearchAndNavigationTarget() async throws {
        let service = SearchTestFixtures.service(corpus: SearchTestFixtures.focusedCorpus())
        try await service.rebuildExactIndex { _ in }

        _ = try await service.exactSearch(ExactSearchQuery(text: "adapter"), page: PageRequest(limit: 5))
        let suggestions = try await service.typeaheadSuggestions(for: "des", limit: 5)
        XCTAssertTrue(suggestions.contains { $0.text == "Design review" })

        let recent = try await service.recentSearches(limit: 5)
        XCTAssertEqual(recent.first?.text, "adapter")
        XCTAssertEqual(recent.first?.mode, .exact)

        let page = try await service.exactSearch(ExactSearchQuery(text: "adapter"), page: PageRequest(limit: 1))
        let target = try service.navigationTarget(for: try XCTUnwrap(page.items.first))
        XCTAssertEqual(target.conversationID, "conversation.design")
        XCTAssertEqual(target.preferredAnchor, "message.design.3")
    }

    func testNaturalLanguageInterpretationStaysLocalAndParsesFilters() {
        let service = SearchTestFixtures.service(corpus: SearchTestFixtures.focusedCorpus())
        let query = service.interpretNaturalLanguageQuery("invoice service:sms after:2026-01-03 from:contact.ava")

        XCTAssertEqual(query.text, "invoice")
        XCTAssertEqual(query.filters.service, .sms)
        XCTAssertEqual(query.filters.senderID, "contact.ava")
        XCTAssertNotNil(query.filters.sentAfter)
    }

    func testSemanticFallbackReturnsRankedOfflineResults() async throws {
        let service = SearchTestFixtures.service(
            corpus: SearchTestFixtures.focusedCorpus(),
            embedder: HashingSemanticEmbedder(dimension: 96)
        )
        try await service.rebuildExactIndex { _ in }
        try await service.rebuildSemanticIndex { _ in }

        let snippets = try await service.semanticSearch(
            SemanticSearchQuery(text: "meal and espresso", limit: 3, minimumSimilarity: 0.55)
        )

        XCTAssertEqual(snippets.first?.conversationID, "conversation.lunch")
        XCTAssertGreaterThanOrEqual(snippets.first?.similarity ?? 0, 0.55)

        let hybrid = try await service.hybridSearch(
            HybridSearchQuery(text: "expense bill", minimumSemanticSimilarity: 0.52),
            page: PageRequest(limit: 5)
        )
        XCTAssertTrue(hybrid.items.contains { $0.conversationID == "conversation.receipts" })
    }

    func testIndexStateMigrationAndInvalidation() async throws {
        let service = SearchTestFixtures.service(corpus: SearchTestFixtures.focusedCorpus())
        try await service.prepare()

        let emptyState = try await service.localIndexState()
        XCTAssertEqual(emptyState.schemaVersion, 1)
        XCTAssertEqual(emptyState.documentCount, 0)

        try await service.rebuildExactIndex { _ in }
        let populatedState = try await service.localIndexState()
        XCTAssertGreaterThan(populatedState.documentCount, 0)

        try await service.invalidateIndex(for: "conversation.design")
        let page = try await service.exactSearch(
            ExactSearchQuery(text: "adapter"),
            page: PageRequest(limit: 10)
        )
        XCTAssertTrue(page.items.isEmpty)
    }

    func testSemanticIndexCanResumeAfterCancellation() async throws {
        let service = SearchTestFixtures.service(
            corpus: SearchTestFixtures.largeCorpus(messageCount: 300, needleEvery: 17),
            batchSize: 10,
            embedder: SlowHashingEmbedder()
        )
        try await service.rebuildExactIndex { _ in }

        let task = Task {
            try await service.rebuildSemanticIndex { _ in }
        }
        // Cancel once the first batch of embeddings has actually landed, rather
        // than after a fixed wall-clock delay. A fixed sleep is flaky on loaded
        // CI runners — it can fire before any batch persists or after the whole
        // (deliberately slow) corpus finishes. Polling the persisted count makes
        // "cancelled mid-flight" deterministic regardless of runner speed.
        var polls = 0
        while try await service.localIndexState().semanticEmbeddingCount == 0, polls < 400 {
            try await Task.sleep(nanoseconds: 5_000_000)
            polls += 1
        }
        task.cancel()

        do {
            try await task.value
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let partiallyIndexed = try await service.localIndexState()
        XCTAssertGreaterThan(partiallyIndexed.semanticEmbeddingCount, 0)
        XCTAssertGreaterThan(partiallyIndexed.pendingSemanticEmbeddingCount, 0)

        try await service.rebuildSemanticIndex { _ in }
        let complete = try await service.localIndexState()
        XCTAssertEqual(complete.pendingSemanticEmbeddingCount, 0)
    }

    func testRepeatedExactRebuildPreservesSemanticEmbeddings() async throws {
        // Regression: the live-data observer re-runs the exact rebuild whenever the
        // Messages DB changes. If that rebuild rewrites unchanged documents it
        // cascade-deletes their semantic embeddings, forcing a full corpus re-embed
        // on every message — the source of the background-indexing churn.
        let service = SearchTestFixtures.service(
            corpus: SearchTestFixtures.focusedCorpus(),
            embedder: HashingSemanticEmbedder(dimension: 96)
        )
        try await service.rebuildExactIndex { _ in }
        try await service.rebuildSemanticIndex { _ in }

        let indexed = try await service.localIndexState()
        XCTAssertGreaterThan(indexed.semanticEmbeddingCount, 0)
        XCTAssertEqual(indexed.pendingSemanticEmbeddingCount, 0)

        // Re-running the exact rebuild over the same corpus must not invalidate
        // the embeddings that are already up to date.
        try await service.rebuildExactIndex { _ in }
        let afterRerun = try await service.localIndexState()
        XCTAssertEqual(afterRerun.semanticEmbeddingCount, indexed.semanticEmbeddingCount)
        XCTAssertEqual(afterRerun.pendingSemanticEmbeddingCount, 0)
    }

    func testExactSearchFirstPageIsFastOnSyntheticLargeFixture() async throws {
        let service = SearchTestFixtures.service(
            corpus: SearchTestFixtures.largeCorpus(messageCount: 8_000, needleEvery: 40),
            batchSize: 400
        )
        try await service.rebuildExactIndex { _ in }

        let start = Date()
        let page = try await service.exactSearch(
            ExactSearchQuery(text: "searchable needle invoice"),
            page: PageRequest(limit: 25)
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(page.items.count, 25)
        XCTAssertEqual(page.totalCount, 200)
        XCTAssertLessThan(elapsed, 1.0, "FTS first page should be comfortably sub-second on the synthetic fixture.")
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    var last: Double? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }

    func record(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}
