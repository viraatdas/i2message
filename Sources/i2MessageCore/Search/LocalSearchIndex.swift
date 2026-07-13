import Foundation
import GRDB

actor LocalSearchIndex {
    private let databaseURL: URL
    private let semanticScanLimit: Int
    private var databasePool: DatabasePool?
    private var prepared = false

    init(databaseURL: URL, semanticScanLimit: Int) {
        self.databaseURL = databaseURL
        self.semanticScanLimit = semanticScanLimit
    }

    func prepare() throws {
        if prepared {
            return
        }

        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.readonly = false
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        let pool = try DatabasePool(path: databaseURL.path, configuration: configuration)
        try Self.migrator.migrate(pool)

        databasePool = pool
        prepared = true
    }

    func state(modelIdentifier: String) throws -> LocalSearchIndexState {
        let pool = try pool()
        return try pool.read { db in
            let documentCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM search_documents") ?? 0
            let semanticEmbeddingCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM semantic_embeddings WHERE model_id = ?",
                arguments: [modelIdentifier]
            ) ?? 0
            let pendingSemanticEmbeddingCount = try Int.fetchOne(
                db,
                sql: """
                WITH eligible AS (\(semanticEligibilitySQL))
                SELECT COUNT(*)
                FROM eligible el
                JOIN search_documents d ON d.doc_id = el.doc_id
                LEFT JOIN semantic_embeddings e
                    ON e.doc_id = d.doc_id
                    AND e.model_id = ?
                    AND e.hash = d.hash
                WHERE e.doc_id IS NULL
                """,
                arguments: [semanticScanLimit, modelIdentifier]
            ) ?? documentCount

            return LocalSearchIndexState(
                schemaVersion: 1,
                documentCount: documentCount,
                semanticEmbeddingCount: semanticEmbeddingCount,
                pendingSemanticEmbeddingCount: pendingSemanticEmbeddingCount
            )
        }
    }

    func markRebuildComplete(namespace: String) throws {
        try setMetadataValue("complete", forKey: "\(namespace).state")
    }

    func documentCount(kind: SearchResultKind) throws -> Int {
        let pool = try pool()
        return try pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM search_documents WHERE kind = ?",
                arguments: [kind.rawValue]
            ) ?? 0
        }
    }

    /// Per-conversation content signatures recorded by completed indexing
    /// passes. A rebuild skips streaming any conversation whose signature is
    /// unchanged, which is what makes reindexing a large library incremental
    /// and resumable (interrupted passes simply lack signatures for the
    /// conversations they never finished).
    func conversationSignatures() throws -> [String: String] {
        let pool = try pool()
        return try pool.read { db in
            var result: [String: String] = [:]
            let rows = try Row.fetchAll(db, sql: "SELECT conversation_id, signature FROM indexed_conversations")
            result.reserveCapacity(rows.count)
            for row in rows {
                let conversationID: String = row["conversation_id"]
                let signature: String = row["signature"]
                result[conversationID] = signature
            }
            return result
        }
    }

    func setConversationSignature(_ signature: String, conversationID: String) throws {
        let pool = try pool()
        try pool.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO indexed_conversations (conversation_id, signature, updated_at)
                VALUES (?, ?, ?)
                """,
                arguments: [conversationID, signature, Date().timeIntervalSince1970]
            )
        }
    }

    /// doc_id → content hash for the given documents only, so a streaming
    /// rebuild never has to hold the full 700k-row hash map in memory. Lets a
    /// rebuild skip rows whose content is unchanged, which avoids needlessly
    /// replacing them (a replace cascade-deletes the row's semantic embedding).
    func documentHashes(for documentIDs: [String]) throws -> [String: String] {
        guard !documentIDs.isEmpty else {
            return [:]
        }

        let pool = try pool()
        return try pool.read { db in
            var result: [String: String] = [:]
            result.reserveCapacity(documentIDs.count)
            let chunkSize = 500
            var start = 0
            while start < documentIDs.count {
                let chunk = Array(documentIDs[start..<min(start + chunkSize, documentIDs.count)])
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT doc_id, hash FROM search_documents WHERE doc_id IN (\(placeholders))",
                    arguments: StatementArguments(chunk)
                )
                for row in rows {
                    let docID: String = row["doc_id"]
                    let hash: String = row["hash"]
                    result[docID] = hash
                }
                start += chunkSize
            }
            return result
        }
    }

    func upsertDocuments(_ documents: [SearchIndexDocument]) throws {
        guard !documents.isEmpty else {
            return
        }

        let pool = try pool()
        try pool.write { db in
            for document in documents {
                let rowID = Self.rowID(for: document.id)
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO search_documents (
                        doc_id, fts_rowid, kind, conversation_id, message_id, contact_id,
                        attachment_id, title, subtitle, body, service, sender_id, sent_at, hash,
                        updated_at
                    ) VALUES (
                        :docID, :rowID, :kind, :conversationID, :messageID, :contactID,
                        :attachmentID, :title, :subtitle, :body, :service, :senderID, :sentAt,
                        :hash, :updatedAt
                    )
                    """,
                    arguments: [
                        "docID": document.id,
                        "rowID": rowID,
                        "kind": document.kind.rawValue,
                        "conversationID": document.conversationID?.rawValue,
                        "messageID": document.messageID?.rawValue,
                        "contactID": document.contactID?.rawValue,
                        "attachmentID": document.attachmentID?.rawValue,
                        "title": document.title,
                        "subtitle": document.subtitle,
                        "body": document.body,
                        "service": document.service?.rawValue,
                        "senderID": document.senderID?.rawValue,
                        "sentAt": document.date?.timeIntervalSince1970,
                        "hash": document.hash,
                        "updatedAt": Date().timeIntervalSince1970
                    ]
                )

                try db.execute(sql: "DELETE FROM search_fts WHERE rowid = ?", arguments: [rowID])
                try db.execute(
                    sql: """
                    INSERT INTO search_fts (
                        rowid, doc_id, kind, conversation_id, message_id, contact_id,
                        attachment_id, title, subtitle, body, service, sender_id, sent_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        rowID,
                        document.id,
                        document.kind.rawValue,
                        document.conversationID?.rawValue,
                        document.messageID?.rawValue,
                        document.contactID?.rawValue,
                        document.attachmentID?.rawValue,
                        document.title,
                        document.subtitle,
                        document.body,
                        document.service?.rawValue,
                        document.senderID?.rawValue,
                        document.date?.timeIntervalSince1970
                    ]
                )
            }
        }
    }

    /// Removes stale documents inside one conversation (messages that were
    /// deleted or retracted since the last pass). Scoped per conversation so
    /// the sweep never scans the whole table.
    func deleteDocuments(conversationID: String, excluding validIDs: Set<String>) throws {
        let pool = try pool()
        try pool.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT doc_id, fts_rowid FROM search_documents WHERE conversation_id = ?",
                arguments: [conversationID]
            )
            for row in rows {
                let docID: String = row["doc_id"]
                guard !validIDs.contains(docID) else {
                    continue
                }

                let rowID: Int64 = row["fts_rowid"]
                try db.execute(sql: "DELETE FROM search_fts WHERE rowid = ?", arguments: [rowID])
                try db.execute(sql: "DELETE FROM semantic_embeddings WHERE doc_id = ?", arguments: [docID])
                try db.execute(sql: "DELETE FROM search_documents WHERE doc_id = ?", arguments: [docID])
            }
        }
    }

    /// Removes documents for conversations that no longer exist and contact
    /// documents for contacts that disappeared. Works off the small distinct
    /// conversation/contact id sets rather than scanning every document row.
    func pruneDocuments(validConversationIDs: Set<String>, validContactDocumentIDs: Set<String>) throws {
        let pool = try pool()

        let staleConversationIDs: [String] = try pool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT DISTINCT conversation_id FROM search_documents WHERE conversation_id IS NOT NULL"
            ).filter { !validConversationIDs.contains($0) }
        }

        let staleContactDocIDs: [String] = try pool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT doc_id FROM search_documents WHERE kind = 'contact'"
            ).filter { !validContactDocumentIDs.contains($0) }
        }

        guard !staleConversationIDs.isEmpty || !staleContactDocIDs.isEmpty else {
            return
        }

        try pool.write { db in
            for conversationID in staleConversationIDs {
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT doc_id, fts_rowid FROM search_documents WHERE conversation_id = ?",
                    arguments: [conversationID]
                )
                for row in rows {
                    let docID: String = row["doc_id"]
                    let rowID: Int64 = row["fts_rowid"]
                    try db.execute(sql: "DELETE FROM search_fts WHERE rowid = ?", arguments: [rowID])
                    try db.execute(sql: "DELETE FROM semantic_embeddings WHERE doc_id = ?", arguments: [docID])
                    try db.execute(sql: "DELETE FROM search_documents WHERE doc_id = ?", arguments: [docID])
                }
                try db.execute(
                    sql: "DELETE FROM indexed_conversations WHERE conversation_id = ?",
                    arguments: [conversationID]
                )
            }

            for docID in staleContactDocIDs {
                let rowID = try Int64.fetchOne(
                    db,
                    sql: "SELECT fts_rowid FROM search_documents WHERE doc_id = ?",
                    arguments: [docID]
                )
                if let rowID {
                    try db.execute(sql: "DELETE FROM search_fts WHERE rowid = ?", arguments: [rowID])
                }
                try db.execute(sql: "DELETE FROM semantic_embeddings WHERE doc_id = ?", arguments: [docID])
                try db.execute(sql: "DELETE FROM search_documents WHERE doc_id = ?", arguments: [docID])
            }
        }
    }

    func invalidateDocuments(conversationID: ConversationID?) throws {
        let pool = try pool()
        try pool.write { db in
            let rows: [Row]
            if let conversationID {
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT doc_id, fts_rowid FROM search_documents WHERE conversation_id = ?",
                    arguments: [conversationID.rawValue]
                )
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT doc_id, fts_rowid FROM search_documents")
            }

            for row in rows {
                let docID: String = row["doc_id"]
                let rowID: Int64 = row["fts_rowid"]
                try db.execute(sql: "DELETE FROM search_fts WHERE rowid = ?", arguments: [rowID])
                try db.execute(sql: "DELETE FROM semantic_embeddings WHERE doc_id = ?", arguments: [docID])
                try db.execute(sql: "DELETE FROM search_documents WHERE doc_id = ?", arguments: [docID])
            }

            // Drop the affected conversation signatures too, otherwise the next
            // rebuild would consider the invalidated conversations up to date
            // and never re-stream their documents.
            if let conversationID {
                try db.execute(
                    sql: "DELETE FROM indexed_conversations WHERE conversation_id = ?",
                    arguments: [conversationID.rawValue]
                )
            } else {
                try db.execute(sql: "DELETE FROM indexed_conversations")
            }

            try db.execute(sql: "DELETE FROM search_metadata WHERE key LIKE 'exact.%' OR key LIKE 'semantic.%'")
        }
    }

    func exactSearch(_ query: ExactSearchQuery, page: PageRequest) throws -> Page<SearchResult> {
        try exactSearch(text: query.text, filters: LocalSearchFilters(exactQuery: query), page: page)
    }

    func exactSearch(text: String, filters: LocalSearchFilters, page: PageRequest) throws -> Page<SearchResult> {
        guard let ftsQuery = SearchTokenizer.fts5Query(for: text) else {
            return Page(items: [], hasMore: false, totalCount: 0)
        }

        let limit = max(1, min(page.limit, 200))
        let offset = SearchCursor.offset(from: page)
        let filter = sqlFilter(for: filters)
        var arguments: StatementArguments = [ftsQuery]
        arguments += filter.arguments
        arguments += [limit, offset]

        let sql = """
        SELECT
            doc_id, kind, conversation_id, message_id, contact_id, attachment_id,
            title, subtitle, body, service, sender_id, sent_at,
            bm25(search_fts, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 5.0, 2.0, 1.0, 0.0, 0.0, 0.0) AS rank
        FROM search_fts
        WHERE search_fts MATCH ?
        \(filter.clause)
        ORDER BY rank ASC, COALESCE(sent_at, 0) DESC, doc_id ASC
        LIMIT ? OFFSET ?
        """

        let countSQL = """
        SELECT COUNT(*)
        FROM search_fts
        WHERE search_fts MATCH ?
        \(filter.clause)
        """

        let pool = try pool()
        return try pool.read { db in
            var countArguments: StatementArguments = [ftsQuery]
            countArguments += filter.arguments
            let totalCount = try Int.fetchOne(db, sql: countSQL, arguments: countArguments) ?? 0
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            let results = rows.map { row in
                searchResult(from: row, query: text)
            }
            return SearchCursor.page(items: results, requestedLimit: limit, offset: offset, totalCount: totalCount)
        }
    }

    func typeaheadSuggestions(for text: String, limit: Int) throws -> [SearchSuggestion] {
        guard let ftsQuery = SearchTokenizer.fts5Query(for: text) else {
            return []
        }

        let pool = try pool()
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT doc_id, kind, title, subtitle,
                       bm25(search_fts, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 5.0, 2.0, 1.0) AS rank
                FROM search_fts
                WHERE search_fts MATCH ?
                ORDER BY rank ASC, COALESCE(sent_at, 0) DESC
                LIMIT ?
                """,
                arguments: [ftsQuery, max(1, min(limit, 20))]
            )

            var seen = Set<String>()
            return rows.compactMap { row in
                let title: String = row["title"]
                guard seen.insert(title).inserted else {
                    return nil
                }

                let rank: Double = row["rank"]
                let kind = SearchResultKind(rawValue: row["kind"] as String) ?? .message
                return SearchSuggestion(
                    id: row["doc_id"],
                    text: title,
                    kind: kind,
                    subtitle: row["subtitle"],
                    score: score(fromRank: rank, date: nil)
                )
            }
        }
    }

    func recordRecentSearch(text: String, mode: SearchMode, date: Date) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let id = StableHash.digest("\(mode.rawValue):\(SearchTokenizer.normalized(trimmed))")
        let pool = try pool()
        try pool.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO recent_searches (id, text, mode, created_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [id, trimmed, mode.rawValue, date.timeIntervalSince1970]
            )
            try db.execute(
                sql: """
                DELETE FROM recent_searches
                WHERE id NOT IN (
                    SELECT id FROM recent_searches ORDER BY created_at DESC LIMIT 50
                )
                """
            )
        }
    }

    func recentSearches(limit: Int) throws -> [RecentSearch] {
        let pool = try pool()
        return try pool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, text, mode, created_at FROM recent_searches ORDER BY created_at DESC LIMIT ?",
                arguments: [max(1, min(limit, 50))]
            ).map { row in
                RecentSearch(
                    id: row["id"],
                    text: row["text"],
                    mode: SearchMode(rawValue: row["mode"] as String) ?? .exact,
                    createdAt: Date(timeIntervalSince1970: row["created_at"])
                )
            }
        }
    }

    /// Only the most recent `semanticScanLimit` documents are eligible for
    /// semantic embedding. Exact FTS search still covers everything; embedding
    /// the full history locally is prohibitive on large libraries, so the
    /// semantic layer is bounded to the newest slice, embedded newest-first.
    private var semanticEligibilitySQL: String {
        """
        SELECT doc_id, hash FROM search_documents
        ORDER BY sent_at DESC, doc_id ASC
        LIMIT ?
        """
    }

    func documentsNeedingSemanticEmbeddings(modelIdentifier: String, limit: Int) throws -> [SearchIndexDocument] {
        let pool = try pool()
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                WITH eligible AS (\(semanticEligibilitySQL))
                SELECT d.*
                FROM eligible el
                JOIN search_documents d ON d.doc_id = el.doc_id
                LEFT JOIN semantic_embeddings e
                    ON e.doc_id = d.doc_id
                    AND e.model_id = ?
                    AND e.hash = d.hash
                WHERE e.doc_id IS NULL
                ORDER BY d.sent_at DESC, d.doc_id ASC
                LIMIT ?
                """,
                arguments: [semanticScanLimit, modelIdentifier, max(1, limit)]
            )
            return rows.map(document(from:))
        }
    }

    func semanticPendingCount(modelIdentifier: String) throws -> Int {
        let pool = try pool()
        return try pool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                WITH eligible AS (\(semanticEligibilitySQL))
                SELECT COUNT(*)
                FROM eligible el
                JOIN search_documents d ON d.doc_id = el.doc_id
                LEFT JOIN semantic_embeddings e
                    ON e.doc_id = d.doc_id
                    AND e.model_id = ?
                    AND e.hash = d.hash
                WHERE e.doc_id IS NULL
                """,
                arguments: [semanticScanLimit, modelIdentifier]
            ) ?? 0
        }
    }

    func upsertSemanticEmbeddings(_ embeddings: [SemanticEmbeddingRecord]) throws {
        guard !embeddings.isEmpty else {
            return
        }

        let pool = try pool()
        try pool.write { db in
            for embedding in embeddings {
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO semantic_embeddings (
                        doc_id, model_id, dimension, vector, hash, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        embedding.document.id,
                        embedding.modelIdentifier,
                        embedding.dimension,
                        embedding.vectorData,
                        embedding.document.hash,
                        embedding.updatedAt.timeIntervalSince1970
                    ]
                )
            }
        }
    }

    func semanticCandidates(filters: LocalSearchFilters, modelIdentifier: String) throws -> [SemanticCandidate] {
        let filter = sqlDocumentFilter(for: filters)
        var arguments: StatementArguments = [modelIdentifier]
        arguments += filter.arguments
        arguments += [semanticScanLimit]

        let pool = try pool()
        return try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT d.*, e.dimension, e.vector
                FROM semantic_embeddings e
                JOIN search_documents d ON d.doc_id = e.doc_id
                WHERE e.model_id = ?
                  AND e.hash = d.hash
                \(filter.clause)
                ORDER BY COALESCE(d.sent_at, 0) DESC, d.doc_id ASC
                LIMIT ?
                """,
                arguments: arguments
            ).compactMap { row in
                let dimension: Int = row["dimension"]
                let data: Data = row["vector"]
                let vector = SemanticVector.decode(data, dimension: dimension)
                guard !vector.isEmpty else {
                    return nil
                }
                return SemanticCandidate(document: document(from: row), vector: vector)
            }
        }
    }

    private func metadataValue(_ key: String) throws -> String? {
        let pool = try pool()
        return try pool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM search_metadata WHERE key = ?", arguments: [key])
        }
    }

    private func setMetadataValue(_ value: String, forKey key: String) throws {
        let pool = try pool()
        try pool.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO search_metadata (key, value) VALUES (?, ?)",
                arguments: [key, value]
            )
        }
    }

    private func pool() throws -> DatabasePool {
        guard let databasePool else {
            throw I2MessageError.indexingFailed(reason: "Search index has not been prepared")
        }

        return databasePool
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create local search index") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS search_metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS search_documents (
                doc_id TEXT PRIMARY KEY NOT NULL,
                fts_rowid INTEGER NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                conversation_id TEXT,
                message_id TEXT,
                contact_id TEXT,
                attachment_id TEXT,
                title TEXT NOT NULL,
                subtitle TEXT NOT NULL,
                body TEXT NOT NULL,
                service TEXT,
                sender_id TEXT,
                sent_at REAL,
                hash TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
                doc_id UNINDEXED,
                kind UNINDEXED,
                conversation_id UNINDEXED,
                message_id UNINDEXED,
                contact_id UNINDEXED,
                attachment_id UNINDEXED,
                title,
                subtitle,
                body,
                service UNINDEXED,
                sender_id UNINDEXED,
                sent_at UNINDEXED,
                tokenize = 'unicode61 remove_diacritics 2',
                prefix = '2 3 4'
            )
            """)

            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS semantic_embeddings (
                doc_id TEXT PRIMARY KEY NOT NULL REFERENCES search_documents(doc_id) ON DELETE CASCADE,
                model_id TEXT NOT NULL,
                dimension INTEGER NOT NULL,
                vector BLOB NOT NULL,
                hash TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS recent_searches (
                id TEXT PRIMARY KEY NOT NULL,
                text TEXT NOT NULL,
                mode TEXT NOT NULL,
                created_at REAL NOT NULL
            )
            """)

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_search_documents_conversation ON search_documents(conversation_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_search_documents_sender ON search_documents(sender_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_search_documents_sent_at ON search_documents(sent_at)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_search_documents_service ON search_documents(service)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_semantic_embeddings_model ON semantic_embeddings(model_id)")
        }
        migrator.registerMigration("create conversation index state") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS indexed_conversations (
                conversation_id TEXT PRIMARY KEY NOT NULL,
                signature TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """)
        }
        return migrator
    }

    private static func rowID(for documentID: String) -> Int64 {
        let hash = UInt64(StableHash.digest(documentID), radix: 16) ?? 1
        let masked = hash & 0x7fff_ffff_ffff_ffff
        return Int64(masked == 0 ? 1 : masked)
    }
}

struct SemanticEmbeddingRecord: Sendable {
    var document: SearchIndexDocument
    var modelIdentifier: String
    var dimension: Int
    var vectorData: Data
    var updatedAt: Date
}

struct SemanticCandidate: Sendable {
    var document: SearchIndexDocument
    var vector: [Float]
}

private struct SQLFilter {
    var clause: String
    var arguments: StatementArguments
}

private func sqlFilter(for filters: LocalSearchFilters) -> SQLFilter {
    var clauses: [String] = []
    var arguments = StatementArguments()

    if let conversationID = filters.conversationID {
        clauses.append("AND conversation_id = ?")
        arguments += [conversationID.rawValue]
    }

    if let senderID = filters.senderID {
        clauses.append("AND sender_id = ?")
        arguments += [senderID.rawValue]
    }

    if let service = filters.service {
        clauses.append("AND service = ?")
        arguments += [service.rawValue]
    }

    if let sentAfter = filters.sentAfter {
        clauses.append("AND sent_at >= ?")
        arguments += [sentAfter.timeIntervalSince1970]
    }

    if let sentBefore = filters.sentBefore {
        clauses.append("AND sent_at <= ?")
        arguments += [sentBefore.timeIntervalSince1970]
    }

    if !filters.includeAttachments {
        clauses.append("AND kind <> 'attachment'")
    }

    return SQLFilter(clause: clauses.joined(separator: "\n"), arguments: arguments)
}

private func sqlDocumentFilter(for filters: LocalSearchFilters) -> SQLFilter {
    var filter = sqlFilter(for: filters)
    if !filter.clause.isEmpty {
        filter.clause = filter.clause
            .replacingOccurrences(of: "conversation_id", with: "d.conversation_id")
            .replacingOccurrences(of: "sender_id", with: "d.sender_id")
            .replacingOccurrences(of: "service", with: "d.service")
            .replacingOccurrences(of: "sent_at", with: "d.sent_at")
            .replacingOccurrences(of: "kind", with: "d.kind")
    }
    return filter
}

private func searchResult(from row: Row, query: String) -> SearchResult {
    let title: String = row["title"]
    let subtitle: String = row["subtitle"]
    let body: String = row["body"]
    let date = dateValue(row["sent_at"] as Double?)
    let snippet = SearchHighlighter.snippet(title: title, subtitle: subtitle, body: body, query: query)
    let rank: Double = row["rank"]
    let kind = SearchResultKind(rawValue: row["kind"] as String) ?? .message

    return SearchResult(
        id: row["doc_id"],
        kind: kind,
        conversationID: optionalRaw(row["conversation_id"]).map(ConversationID.init(rawValue:)),
        messageID: optionalRaw(row["message_id"]).map(MessageID.init(rawValue:)),
        contactID: optionalRaw(row["contact_id"]).map(ContactID.init(rawValue:)),
        attachmentID: optionalRaw(row["attachment_id"]).map(AttachmentID.init(rawValue:)),
        title: title,
        subtitle: subtitle,
        snippet: snippet.text,
        matchedRanges: snippet.ranges,
        score: score(fromRank: rank, date: date),
        date: date
    )
}

private func document(from row: Row) -> SearchIndexDocument {
    let date = dateValue(row["sent_at"] as Double?)
    let kind = SearchResultKind(rawValue: row["kind"] as String) ?? .message

    return SearchIndexDocument(
        id: row["doc_id"],
        kind: kind,
        conversationID: optionalRaw(row["conversation_id"]).map(ConversationID.init(rawValue:)),
        messageID: optionalRaw(row["message_id"]).map(MessageID.init(rawValue:)),
        contactID: optionalRaw(row["contact_id"]).map(ContactID.init(rawValue:)),
        attachmentID: optionalRaw(row["attachment_id"]).map(AttachmentID.init(rawValue:)),
        title: row["title"],
        subtitle: row["subtitle"],
        body: row["body"],
        service: optionalRaw(row["service"]).flatMap(MessageService.init(rawValue:)),
        senderID: optionalRaw(row["sender_id"]).map(ContactID.init(rawValue:)),
        date: date,
        hash: row["hash"]
    )
}

private func optionalRaw(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
        return nil
    }
    return value
}

private func dateValue(_ value: Double?) -> Date? {
    value.map { Date(timeIntervalSince1970: $0) }
}

private func score(fromRank rank: Double, date: Date?) -> Double {
    let lexicalScore = max(0.0001, -rank)
    let recencyBoost = date.map { min(0.15, max(0, $0.timeIntervalSinceReferenceDate / 40_000_000_000)) } ?? 0
    return lexicalScore + recencyBoost
}
