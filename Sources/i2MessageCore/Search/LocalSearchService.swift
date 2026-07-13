import Foundation

public final class LocalSearchService: SearchProviding, SearchIndexing, @unchecked Sendable {
    private let index: LocalSearchIndex
    private let corpusProvider: any SearchIndexCorpusProviding
    private let embedder: any SemanticEmbeddingProviding
    private let indexingBatchSize: Int
    private let semanticCandidateLimit: Int

    public init(
        indexURL: URL,
        corpusProvider: any SearchIndexCorpusProviding,
        embedder: any SemanticEmbeddingProviding = AutomaticLocalSemanticEmbedder(),
        indexingBatchSize: Int = 500,
        semanticCandidateLimit: Int = 20_000
    ) {
        self.index = LocalSearchIndex(databaseURL: indexURL, semanticScanLimit: semanticCandidateLimit)
        self.corpusProvider = corpusProvider
        self.embedder = embedder
        self.indexingBatchSize = max(25, indexingBatchSize)
        self.semanticCandidateLimit = max(100, semanticCandidateLimit)
    }

    public func prepare() async throws {
        try await index.prepare()
    }

    public func exactSearch(_ query: ExactSearchQuery, page: PageRequest) async throws -> Page<SearchResult> {
        try Task.checkCancellation()
        try await prepare()
        try await index.recordRecentSearch(text: query.text, mode: .exact, date: Date())
        return try await index.exactSearch(query, page: page)
    }

    public func exactSearch(text: String, filters: LocalSearchFilters, page: PageRequest) async throws -> Page<SearchResult> {
        try Task.checkCancellation()
        try await prepare()
        try await index.recordRecentSearch(text: text, mode: .exact, date: Date())
        return try await index.exactSearch(text: text, filters: filters, page: page)
    }

    public func semanticSearch(_ query: SemanticSearchQuery) async throws -> [SemanticSnippet] {
        try Task.checkCancellation()
        try await prepare()
        try await index.recordRecentSearch(text: query.text, mode: .semantic, date: Date())

        let filters = LocalSearchFilters(conversationID: query.conversationID)
        let vector = try await embedder.embedding(for: query.text)
        let candidates = try await index.semanticCandidates(filters: filters, modelIdentifier: embedder.modelIdentifier)
        let now = Date()

        return candidates
            .compactMap { candidate -> SemanticSnippet? in
                guard let conversationID = candidate.document.conversationID else {
                    return nil
                }

                let cosine = SemanticVector.cosine(vector, candidate.vector)
                let similarity = max(0, min(1, (cosine + 1) / 2))
                guard similarity >= query.minimumSimilarity else {
                    return nil
                }

                let snippet = SearchHighlighter.snippet(
                    title: candidate.document.title,
                    subtitle: candidate.document.subtitle,
                    body: candidate.document.body,
                    query: query.text
                )

                return SemanticSnippet(
                    id: "semantic:\(candidate.document.id)",
                    conversationID: conversationID,
                    sourceMessageIDs: candidate.document.messageID.map { [$0] } ?? [],
                    text: snippet.text,
                    similarity: similarity,
                    embeddingModelIdentifier: embedder.modelIdentifier,
                    generatedAt: now
                )
            }
            .sorted { left, right in
                if left.similarity == right.similarity {
                    return left.generatedAt > right.generatedAt
                }
                return left.similarity > right.similarity
            }
            .prefix(max(1, min(query.limit, semanticCandidateLimit)))
            .map { $0 }
    }

    public func hybridSearch(_ query: HybridSearchQuery, page: PageRequest) async throws -> Page<SearchResult> {
        try Task.checkCancellation()
        try await prepare()
        try await index.recordRecentSearch(text: query.text, mode: .hybrid, date: Date())

        let offset = SearchCursor.offset(from: page)
        let expandedLimit = max(page.limit + offset, min(200, page.limit * 8))
        let exactPage = try await index.exactSearch(
            text: query.text,
            filters: query.filters,
            page: PageRequest(limit: expandedLimit)
        )
        let semanticResults = try await semanticResults(
            text: query.text,
            filters: query.filters,
            minimumSimilarity: query.minimumSemanticSimilarity,
            limit: expandedLimit
        )

        var merged: [String: SearchResult] = [:]
        for result in exactPage.items {
            var weighted = result
            weighted.score = result.score * query.exactWeight
            merged[weighted.id] = weighted
        }

        for result in semanticResults {
            var weighted = result
            weighted.score = result.score * query.semanticWeight
            if let existing = merged[weighted.id] {
                var combined = existing
                combined.score += weighted.score
                combined.kind = existing.kind
                merged[weighted.id] = combined
            } else {
                merged[weighted.id] = weighted
            }
        }

        let ranked = merged.values.sorted { left, right in
            if left.score == right.score {
                return (left.date ?? .distantPast) > (right.date ?? .distantPast)
            }
            return left.score > right.score
        }

        let pageItems = Array(ranked.dropFirst(offset).prefix(max(1, page.limit)))
        return SearchCursor.page(
            items: pageItems,
            requestedLimit: page.limit,
            offset: offset,
            totalCount: ranked.count
        )
    }

    public func typeaheadSuggestions(for text: String, limit: Int = 8) async throws -> [SearchSuggestion] {
        try Task.checkCancellation()
        try await prepare()
        return try await index.typeaheadSuggestions(for: text, limit: limit)
    }

    public func recentSearches(limit: Int = 10) async throws -> [RecentSearch] {
        try await prepare()
        return try await index.recentSearches(limit: limit)
    }

    public func interpretNaturalLanguageQuery(_ text: String) -> HybridSearchQuery {
        var tokensToRemove = Set<String>()
        var filters = LocalSearchFilters()
        let words = text.split(separator: " ").map(String.init)

        for word in words {
            let normalized = SearchTokenizer.normalized(word)
            if let service = parseServiceToken(normalized) {
                filters.service = service
                tokensToRemove.insert(word)
            } else if let date = parseDateToken(normalized, prefix: "after:") {
                filters.sentAfter = date
                tokensToRemove.insert(word)
            } else if let date = parseDateToken(normalized, prefix: "before:") {
                filters.sentBefore = date
                tokensToRemove.insert(word)
            } else if normalized.hasPrefix("from:") {
                filters.senderID = ContactID(rawValue: String(normalized.dropFirst("from:".count)))
                tokensToRemove.insert(word)
            } else if normalized.hasPrefix("in:") {
                filters.conversationID = ConversationID(rawValue: String(normalized.dropFirst("in:".count)))
                tokensToRemove.insert(word)
            }
        }

        let cleaned = words
            .filter { !tokensToRemove.contains($0) }
            .joined(separator: " ")

        return HybridSearchQuery(text: cleaned.isEmpty ? text : cleaned, filters: filters)
    }

    public func navigationTarget(for result: SearchResult) throws -> SearchNavigationTarget {
        guard let conversationID = result.conversationID else {
            throw I2MessageError.notFound(resource: "conversation", id: result.id)
        }

        return SearchNavigationTarget(
            conversationID: conversationID,
            messageID: result.messageID,
            attachmentID: result.attachmentID,
            preferredAnchor: result.messageID,
            resultKind: result.kind
        )
    }

    public func localIndexState() async throws -> LocalSearchIndexState {
        try await prepare()
        return try await index.state(modelIdentifier: embedder.modelIdentifier)
    }

    /// Number of indexed documents of one kind (e.g. message documents only).
    /// Used by diagnostics and the real-database verification harness.
    func indexedDocumentCount(kind: SearchResultKind) async throws -> Int {
        try await prepare()
        return try await index.documentCount(kind: kind)
    }

    /// Streams the corpus one conversation at a time so the full library never
    /// has to be materialized in memory, no matter how large the Messages
    /// history is. Conversations whose signature is unchanged since the last
    /// completed pass are skipped without touching their message history, which
    /// keeps background reindexing incremental; an interrupted pass resumes by
    /// skipping the conversations it already finished.
    public func rebuildExactIndex(progress: @Sendable @escaping (Double) -> Void) async throws {
        try Task.checkCancellation()
        try await prepare()

        let skeleton = try await corpusProvider.corpusSkeleton()
        // Deterministic order so repeated/resumed passes walk the same sequence.
        let conversations = skeleton.conversations.sorted { $0.id.rawValue < $1.id.rawValue }
        let contactsByID = Dictionary(skeleton.contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Conversation and contact documents are small; upsert the changed ones
        // up front, then drop documents whose conversation or contact vanished.
        let skeletonDocuments = SearchDocumentBuilder.skeletonDocuments(
            conversations: conversations,
            contacts: skeleton.contacts
        )
        try await upsertChangedDocuments(skeletonDocuments)
        try await index.pruneDocuments(
            validConversationIDs: Set(conversations.map(\.id.rawValue)),
            validContactDocumentIDs: Set(skeletonDocuments.filter { $0.kind == .contact }.map(\.id))
        )

        let total = conversations.count
        guard total > 0 else {
            progress(1)
            try await index.markRebuildComplete(namespace: "exact")
            return
        }
        progress(0)

        let storedSignatures = try await index.conversationSignatures()
        var firstError: Error?

        for (position, conversation) in conversations.enumerated() {
            try Task.checkCancellation()
            let signature = SearchDocumentBuilder.conversationSignature(conversation)

            if storedSignatures[conversation.id.rawValue] != signature {
                do {
                    try await indexConversation(conversation, contactsByID: contactsByID)
                    try await index.setConversationSignature(signature, conversationID: conversation.id.rawValue)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // One unreadable conversation must not brick search for the
                    // rest of the library. Its signature stays unset so the next
                    // pass retries it; the first failure is rethrown at the end.
                    firstError = firstError ?? error
                }
            }

            progress(Double(position + 1) / Double(total))
            await Task.yield()
        }

        if let firstError {
            throw firstError
        }

        try await index.markRebuildComplete(namespace: "exact")
        progress(1)
    }

    private func indexConversation(
        _ conversation: Conversation,
        contactsByID: [ContactID: Contact]
    ) async throws {
        var validDocumentIDs: Set<String> = [SearchDocumentBuilder.documentID(for: conversation.id)]

        for try await batch in corpusProvider.messageBatches(in: conversation.id, batchSize: indexingBatchSize) {
            try Task.checkCancellation()
            let documents = SearchDocumentBuilder.messageDocuments(
                for: batch,
                conversation: conversation,
                contactsByID: contactsByID
            )
            validDocumentIDs.formUnion(documents.map(\.id))
            try await upsertChangedDocuments(documents)
            await Task.yield()
        }

        // Sweep documents of messages that disappeared from this conversation
        // (deletions, retractions). Scoped to the conversation so it stays cheap.
        try await index.deleteDocuments(conversationID: conversation.id.rawValue, excluding: validDocumentIDs)
    }

    /// Rewrite only documents that are new or whose content changed. Replacing
    /// an unchanged row would cascade-delete its semantic embedding (see the
    /// semantic_embeddings ON DELETE CASCADE) and force a full re-embed of the
    /// corpus on every new message — the dominant source of background churn.
    private func upsertChangedDocuments(_ documents: [SearchIndexDocument]) async throws {
        var start = 0
        while start < documents.count {
            try Task.checkCancellation()
            let end = min(start + indexingBatchSize, documents.count)
            let chunk = Array(documents[start..<end])
            let existingHashes = try await index.documentHashes(for: chunk.map(\.id))
            let changed = chunk.filter { existingHashes[$0.id] != $0.hash }
            if !changed.isEmpty {
                try await index.upsertDocuments(changed)
            }
            start = end
        }
    }

    public func rebuildSemanticIndex(progress: @Sendable @escaping (Double) -> Void) async throws {
        try Task.checkCancellation()
        try await prepare()

        let initialPending = try await index.semanticPendingCount(modelIdentifier: embedder.modelIdentifier)
        guard initialPending > 0 else {
            progress(1)
            try await index.markRebuildComplete(namespace: "semantic")
            return
        }

        var completed = 0
        progress(0)

        while true {
            try Task.checkCancellation()
            let documents = try await index.documentsNeedingSemanticEmbeddings(
                modelIdentifier: embedder.modelIdentifier,
                limit: indexingBatchSize
            )

            if documents.isEmpty {
                break
            }

            var records: [SemanticEmbeddingRecord] = []
            records.reserveCapacity(documents.count)
            for document in documents {
                try Task.checkCancellation()
                let vector = try await embedder.embedding(for: document.semanticText)
                records.append(
                    SemanticEmbeddingRecord(
                        document: document,
                        modelIdentifier: embedder.modelIdentifier,
                        dimension: vector.count,
                        vectorData: SemanticVector.encode(vector),
                        updatedAt: Date()
                    )
                )
            }

            try await index.upsertSemanticEmbeddings(records)
            completed += records.count
            progress(min(0.999, Double(completed) / Double(initialPending)))
            await Task.yield()
        }

        try await index.markRebuildComplete(namespace: "semantic")
        progress(1)
    }

    public func invalidateIndex(for conversationID: ConversationID?) async throws {
        try await prepare()
        try await index.invalidateDocuments(conversationID: conversationID)
    }

    private func semanticResults(
        text: String,
        filters: LocalSearchFilters,
        minimumSimilarity: Double,
        limit: Int
    ) async throws -> [SearchResult] {
        let vector = try await embedder.embedding(for: text)
        let candidates = try await index.semanticCandidates(filters: filters, modelIdentifier: embedder.modelIdentifier)

        return candidates
            .compactMap { candidate -> SearchResult? in
                let cosine = SemanticVector.cosine(vector, candidate.vector)
                let similarity = max(0, min(1, (cosine + 1) / 2))
                guard similarity >= minimumSimilarity else {
                    return nil
                }

                let snippet = SearchHighlighter.snippet(
                    title: candidate.document.title,
                    subtitle: candidate.document.subtitle,
                    body: candidate.document.body,
                    query: text
                )

                return SearchResult(
                    id: candidate.document.id,
                    kind: candidate.document.kind == .message ? .semanticSnippet : candidate.document.kind,
                    conversationID: candidate.document.conversationID,
                    messageID: candidate.document.messageID,
                    contactID: candidate.document.contactID,
                    attachmentID: candidate.document.attachmentID,
                    title: candidate.document.title,
                    subtitle: candidate.document.subtitle,
                    snippet: snippet.text,
                    matchedRanges: snippet.ranges,
                    score: similarity,
                    date: candidate.document.date
                )
            }
            .sorted { left, right in
                if left.score == right.score {
                    return (left.date ?? .distantPast) > (right.date ?? .distantPast)
                }
                return left.score > right.score
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    private func parseServiceToken(_ token: String) -> MessageService? {
        let value: String
        if token.hasPrefix("service:") {
            value = String(token.dropFirst("service:".count))
        } else {
            value = token
        }

        switch value {
        case "imessage":
            return .iMessage
        case "sms":
            return .sms
        case "mms":
            return .mms
        case "rcs":
            return .rcs
        default:
            return nil
        }
    }

    private func parseDateToken(_ token: String, prefix: String) -> Date? {
        guard token.hasPrefix(prefix) else {
            return nil
        }

        let value = String(token.dropFirst(prefix.count))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
    }
}
