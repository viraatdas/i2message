import XCTest
@testable import i2MessageCore

/// Env-gated verification harness that builds the exact search index from the
/// user's REAL ~/Library/Messages/chat.db (via a private temporary copy) and
/// checks that full-history coverage actually holds on real data.
///
/// Run with:
///   ./scripts/real-db-index-check.sh
/// or:
///   env TEST_RUNNER_I2MESSAGE_REAL_DB_CHECK=1 ./scripts/test.sh
///
/// The harness is read-only with respect to the real database (it clones the
/// files, never opening the originals for writing), works entirely inside a
/// temporary directory, and deletes everything it created on the way out. It
/// prints counts and timings only — never message content or contact names.
final class RealMessagesDatabaseIndexingTests: XCTestCase {
    func testExactIndexCoversFullRealHistory() async throws {
        guard ProcessInfo.processInfo.environment["I2MESSAGE_REAL_DB_CHECK"] == "1" else {
            throw XCTSkip("Set I2MESSAGE_REAL_DB_CHECK=1 (TEST_RUNNER_ prefixed under xcodebuild) to run the real-database check.")
        }

        // The scheme forwards these via $(…) build-setting expansion, so an
        // unset override arrives as an empty string — treat that as unset.
        let sourceURL = ProcessInfo.processInfo.environment["I2MESSAGE_REAL_DB_PATH"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? MessagesStoreConfiguration.defaultDatabaseURL()
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw XCTSkip("Real Messages database is not readable at \(sourceURL.path) (Full Disk Access required).")
        }

        // Work on a clone so the live database is never touched; APFS makes
        // the copy effectively instant.
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("i2message-realdb-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let databaseURL = workspace.appendingPathComponent("chat.db")
        try FileManager.default.copyItem(at: sourceURL, to: databaseURL)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: sourceURL.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.copyItem(
                    at: sidecar,
                    to: URL(fileURLWithPath: databaseURL.path + suffix)
                )
            }
        }

        let configuration = MessagesStoreConfiguration(
            databaseURL: databaseURL,
            attachmentsDirectoryURL: nil,
            pollInterval: 3_600,
            maximumPageSize: 200
        )
        let stack = MessagesDataAccessStack(
            configuration: configuration,
            contactProvider: HarnessContactProvider()
        )

        // Ground truth straight from the copied chat.db: messages the corpus
        // is expected to produce documents for (non-reaction, non-retracted,
        // joined to a chat), and the subset that carries plain text.
        let baseClause = """
        FROM chat_message_join cmj
        JOIN message m ON m.ROWID = cmj.message_id
        WHERE COALESCE(m.associated_message_type, 0) < 2000
          AND COALESCE(m.date_retracted, 0) = 0
        """
        let expectedMessageDocuments = try await scalar(stack, "SELECT COUNT(DISTINCT m.ROWID) AS value \(baseClause)")
        let textMessageCount = try await scalar(
            stack,
            "SELECT COUNT(DISTINCT m.ROWID) AS value \(baseClause) AND m.text IS NOT NULL AND m.text <> ''"
        )
        XCTAssertGreaterThan(textMessageCount, 0, "Expected the real database to contain text messages")

        // Pick a verifiably OLD message up front: the earliest text message
        // long enough to contain distinctive search tokens.
        let oldRows = try await stack.store.read { connection, _ in
            try connection.query(
                """
                SELECT m.ROWID AS message_rowid, cmj.chat_id AS chat_rowid, m.text AS text, m.date AS date_raw
                \(baseClause)
                  AND m.text IS NOT NULL AND LENGTH(m.text) >= 25
                ORDER BY m.date ASC
                LIMIT 25
                """
            ).map { row in
                (
                    rowID: row["message_rowid"].int64 ?? 0,
                    chatRowID: row["chat_rowid"].int64 ?? 0,
                    text: row["text"].string ?? "",
                    dateRaw: row["date_raw"].int64
                )
            }
        }
        let target = try XCTUnwrap(
            oldRows.first { SearchTokenizer.uniqueTokenValues(in: $0.text).contains { $0.count >= 4 } },
            "Expected an old message with searchable tokens"
        )
        let targetTokens = SearchTokenizer.uniqueTokenValues(in: target.text)
            .filter { $0.count >= 4 }
            .prefix(3)
            .joined(separator: " ")
        let targetMessageID = MessagesIdentifier.messageID(rowID: target.rowID)
        let targetConversationID = MessagesIdentifier.conversationID(rowID: target.chatRowID)
        let targetDate = MessagesDateConverter.stableDate(from: target.dateRaw, fallbackRowID: target.rowID)

        // Build the exact index into a temp file, mirroring production wiring
        // (no conversation or message caps, bounded semantic budget).
        let provider = HarnessCorpusProvider(
            conversations: stack.conversations,
            messages: stack.messages,
            contacts: stack.contacts
        )
        let service = LocalSearchService(
            indexURL: workspace.appendingPathComponent("SearchIndex.sqlite"),
            corpusProvider: provider,
            embedder: HashingSemanticEmbedder(),
            indexingBatchSize: 200,
            semanticCandidateLimit: 50_000
        )

        let started = Date()
        let progressLogger = ProgressLogger()
        try await service.rebuildExactIndex { fraction in
            progressLogger.log(fraction: fraction, elapsed: Date().timeIntervalSince(started))
        }
        let elapsed = Date().timeIntervalSince(started)

        let indexedMessageDocuments = try await service.indexedDocumentCount(kind: .message)
        let state = try await service.localIndexState()
        print("""
        [real-db-check] expected message documents (non-reaction, in a chat): \(expectedMessageDocuments)
        [real-db-check] text messages in chat.db: \(textMessageCount)
        [real-db-check] indexed message documents: \(indexedMessageDocuments)
        [real-db-check] total indexed documents (incl. conversations/contacts/attachments): \(state.documentCount)
        [real-db-check] exact index build time: \(String(format: "%.1f", elapsed))s (\(Int(Double(indexedMessageDocuments) / max(elapsed, 0.001))) message docs/s)
        """)

        // (a) Coverage: indexed message documents match the real corpus size.
        XCTAssertGreaterThanOrEqual(
            indexedMessageDocuments,
            textMessageCount,
            "Exact index must cover at least every text message"
        )
        let deviation = abs(Double(indexedMessageDocuments - expectedMessageDocuments)) / Double(max(expectedMessageDocuments, 1))
        XCTAssertLessThanOrEqual(
            deviation,
            0.02,
            "Indexed message documents (\(indexedMessageDocuments)) deviate more than 2% from expected (\(expectedMessageDocuments))"
        )

        // (b) A years-old message is findable via exactSearch. Scope by its
        // conversation and a ±1 day window so the assertion is about that
        // specific message, not whatever ranks first globally.
        let page = try await service.exactSearch(
            text: targetTokens,
            filters: LocalSearchFilters(
                conversationID: targetConversationID,
                sentAfter: targetDate.addingTimeInterval(-86_400),
                sentBefore: targetDate.addingTimeInterval(86_400)
            ),
            page: PageRequest(limit: 200)
        )
        print("[real-db-check] old-message probe: sentAt=\(targetDate), results=\(page.items.count)")
        XCTAssertTrue(
            page.items.contains { $0.messageID == targetMessageID },
            "Expected exactSearch to find the old message (rowid \(target.rowID), sent \(targetDate))"
        )
    }

    private func scalar(_ stack: MessagesDataAccessStack, _ sql: String) async throws -> Int {
        try await stack.store.read { connection, _ in
            try connection.query(sql).first?["value"].int ?? 0
        }
    }
}

/// Streams the copied database through the same repository layer production
/// uses, with no caps — the test-side twin of RepositorySearchIndexCorpusProvider.
private struct HarnessCorpusProvider: SearchIndexCorpusProviding {
    let conversations: any ConversationRepository
    let messages: any MessageRepository
    let contacts: any ContactProviding

    func corpusSkeleton() async throws -> SearchIndexCorpusSkeleton {
        var cursor: PageCursor?
        var allConversations: [Conversation] = []
        repeat {
            let page = try await conversations.conversations(
                page: PageRequest(cursor: cursor, limit: 200),
                filter: ConversationFilter(includeArchived: true)
            )
            allConversations.append(contentsOf: page.items)
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil
        return SearchIndexCorpusSkeleton(
            conversations: allConversations,
            contacts: allConversations.flatMap(\.participants)
        )
    }

    func messageBatches(in conversationID: ConversationID, batchSize: Int) -> AsyncThrowingStream<[Message], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var cursor: PageCursor?
                    repeat {
                        try Task.checkCancellation()
                        let page = try await messages.messages(
                            in: conversationID,
                            page: PageRequest(cursor: cursor, limit: batchSize, direction: .older),
                            around: nil
                        )
                        if !page.items.isEmpty {
                            continuation.yield(page.items)
                        }
                        cursor = page.hasMore ? page.nextCursor : nil
                    } while cursor != nil
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func searchIndexCorpus() async throws -> SearchIndexCorpus {
        let skeleton = try await corpusSkeleton()
        var allMessages: [Message] = []
        for conversation in skeleton.conversations {
            for try await batch in messageBatches(in: conversation.id, batchSize: 200) {
                allMessages.append(contentsOf: batch)
            }
        }
        return SearchIndexCorpus(
            conversations: skeleton.conversations,
            contacts: skeleton.contacts,
            messages: allMessages
        )
    }
}

/// Offline contact provider so the harness never touches the Contacts
/// database (no permission prompts, no personal data resolution). Handles
/// resolve to anonymous fallback contacts.
private struct HarnessContactProvider: ContactProviding, ContactResolving {
    private let resolver = FallbackContactResolver()

    func contacts(matching query: String, page: PageRequest) async throws -> Page<Contact> {
        Page(items: [], hasMore: false, totalCount: 0)
    }

    func contact(id: ContactID) async throws -> Contact {
        throw I2MessageError.notFound(resource: "Contact", id: id.rawValue)
    }

    func contact(for handle: MessageHandle) async throws -> Contact {
        try await resolver.contact(for: handle)
    }

    func contacts(for handles: [MessageHandle]) async throws -> [MessageHandle: Contact] {
        try await resolver.contacts(for: handles)
    }

    func contactID(for handle: MessageHandle) async throws -> ContactID {
        try await resolver.contactID(for: handle)
    }
}

/// Prints coarse progress so a multi-minute full-history build is visibly
/// advancing in the test log.
private final class ProgressLogger: @unchecked Sendable {
    private let lock = NSLock()
    private var lastLoggedDecile = -1

    func log(fraction: Double, elapsed: TimeInterval) {
        let decile = Int(fraction * 10)
        lock.lock()
        defer { lock.unlock() }
        guard decile > lastLoggedDecile else { return }
        lastLoggedDecile = decile
        print("[real-db-check] exact index \(Int(fraction * 100))% after \(String(format: "%.1f", elapsed))s")
    }
}
