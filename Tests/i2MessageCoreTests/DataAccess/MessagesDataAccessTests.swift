import XCTest
@testable import i2MessageCore

final class MessagesDataAccessTests: XCTestCase {
    func testOpenReadOnlyStoreAndDiagnostics() async throws {
        let databaseURL = try SyntheticMessagesDatabase.makeSmallDatabase()
        let configuration = MessagesStoreConfiguration(databaseURL: databaseURL, attachmentsDirectoryURL: nil)
        let store = ReadOnlyMessagesStore(configuration: configuration)
        let descriptor = try await store.openReadOnlyStore()

        XCTAssertEqual(descriptor.databaseURL, databaseURL)
        XCTAssertTrue(descriptor.isReadOnly)

        let diagnostics = await MessagesStoreDiagnosticService(configuration: configuration).runDiagnostics()
        XCTAssertTrue(diagnostics.isUsable)
        XCTAssertEqual(diagnostics.diagnostics.first?.code, .ok)
    }

    func testConversationPageMapsParticipantsUnreadAndLatestMessage() async throws {
        let databaseURL = try SyntheticMessagesDatabase.makeSmallDatabase()
        let stack = makeStack(databaseURL: databaseURL)
        let page = try await stack.conversations.conversations(page: PageRequest(limit: 10), filter: ConversationFilter())

        XCTAssertEqual(page.items.count, 2)
        XCTAssertFalse(page.hasMore)

        let direct = try XCTUnwrap(page.items.first { $0.id == ConversationID(rawValue: "chat:1") })
        XCTAssertEqual(direct.title, "+1 (555) 123-0001")
        XCTAssertEqual(direct.participants.count, 1)
        XCTAssertEqual(direct.unreadCount, 1)
        XCTAssertEqual(direct.lastMessage?.text, "Here is the file")
        XCTAssertEqual(direct.lastMessage?.hasAttachments, true)
        XCTAssertEqual(direct.pinnedRank, 0)

        let group = try XCTUnwrap(page.items.first { $0.id == ConversationID(rawValue: "chat:2") })
        XCTAssertEqual(group.title, "Launch Team")
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.participants.count, 2)
    }

    func testConversationFilteringUsesTitleAndHandles() async throws {
        let databaseURL = try SyntheticMessagesDatabase.makeSmallDatabase()
        let stack = makeStack(databaseURL: databaseURL)

        let titlePage = try await stack.conversations.conversations(
            page: PageRequest(limit: 10),
            filter: ConversationFilter(query: "launch")
        )
        XCTAssertEqual(titlePage.items.map(\.title), ["Launch Team"])

        let handlePage = try await stack.conversations.conversations(
            page: PageRequest(limit: 10),
            filter: ConversationFilter(query: "555")
        )
        XCTAssertTrue(handlePage.items.contains { $0.id == ConversationID(rawValue: "chat:1") })
    }

    func testMessagesPageMapsAttachmentsAndReactions() async throws {
        let databaseURL = try SyntheticMessagesDatabase.makeSmallDatabase()
        let stack = makeStack(databaseURL: databaseURL)
        let page = try await stack.messages.messages(
            in: ConversationID(rawValue: "chat:1"),
            page: PageRequest(limit: 10),
            around: nil
        )

        XCTAssertEqual(page.items.map(\.id), [MessageID(rawValue: "message:2"), MessageID(rawValue: "message:1")])

        let outgoing = try XCTUnwrap(page.items.first)
        XCTAssertEqual(outgoing.body.plainText, "Here is the file")
        XCTAssertEqual(outgoing.direction, .outgoing)
        XCTAssertEqual(outgoing.status, .delivered)
        XCTAssertEqual(outgoing.attachments.count, 1)
        XCTAssertEqual(outgoing.attachments.first?.filename, "photo.png")
        XCTAssertEqual(outgoing.attachments.first?.kind, .image)
        XCTAssertEqual(outgoing.reactions.map(\.kind), [.liked])

        let incoming = page.items[1]
        XCTAssertEqual(incoming.direction, .incoming)
        XCTAssertEqual(incoming.status, .delivered)
        XCTAssertEqual(incoming.senderID, ContactID(rawValue: "handle:1"))
    }

    func testMessagePaginationUsesStableOlderAndNewerCursors() async throws {
        let databaseURL = try SyntheticMessagesDatabase.makeSmallDatabase()
        let stack = makeStack(databaseURL: databaseURL)

        let newestPage = try await stack.messages.messages(
            in: ConversationID(rawValue: "chat:1"),
            page: PageRequest(limit: 1),
            around: nil
        )
        XCTAssertEqual(newestPage.items.map(\.id), [MessageID(rawValue: "message:2")])
        XCTAssertTrue(newestPage.hasMore)

        let olderPage = try await stack.messages.messages(
            in: ConversationID(rawValue: "chat:1"),
            page: PageRequest(cursor: newestPage.nextCursor, limit: 1, direction: .older),
            around: nil
        )
        XCTAssertEqual(olderPage.items.map(\.id), [MessageID(rawValue: "message:1")])

        let newerPage = try await stack.messages.messages(
            in: ConversationID(rawValue: "chat:1"),
            page: PageRequest(cursor: olderPage.previousCursor, limit: 1, direction: .newer),
            around: nil
        )
        XCTAssertEqual(newerPage.items.map(\.id), [MessageID(rawValue: "message:2")])
    }

    func testAttachmentRepositoryLoadsByMessageAndID() async throws {
        let databaseURL = try SyntheticMessagesDatabase.makeSmallDatabase()
        let stack = makeStack(databaseURL: databaseURL)

        let attachments = try await stack.attachments.attachments(for: MessageID(rawValue: "message:2"))
        XCTAssertEqual(attachments.count, 1)

        let attachment = try await stack.attachments.attachment(id: AttachmentID(rawValue: "attachment:1"))
        XCTAssertEqual(attachment.messageID, MessageID(rawValue: "message:2"))
        XCTAssertEqual(attachment.byteCount, 42)
        XCTAssertEqual(attachment.dimensions, AttachmentDimensions(width: 640, height: 480))
    }

    func testMissingDatabaseReportsDiagnosticAndThrowsPermissionSafeError() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).chat.db")
        let configuration = MessagesStoreConfiguration(databaseURL: missingURL, attachmentsDirectoryURL: nil)
        let diagnostics = await MessagesStoreDiagnosticService(configuration: configuration).runDiagnostics()

        XCTAssertFalse(diagnostics.isUsable)
        XCTAssertEqual(diagnostics.diagnostics.first?.code, .databaseMissing)

        do {
            _ = try await ReadOnlyMessagesStore(configuration: configuration).openReadOnlyStore()
            XCTFail("Expected missing database to throw")
        } catch let error as I2MessageError {
            XCTAssertEqual(
                error,
                .databaseUnavailable(path: missingURL.path, reason: "Messages database was not found.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnsupportedSchemaReportsDiagnostic() async throws {
        let databaseURL = try SyntheticMessagesDatabase.makeUnsupportedDatabase()
        let configuration = MessagesStoreConfiguration(databaseURL: databaseURL, attachmentsDirectoryURL: nil)
        let diagnostics = await MessagesStoreDiagnosticService(configuration: configuration).runDiagnostics()

        XCTAssertFalse(diagnostics.isUsable)
        XCTAssertEqual(diagnostics.diagnostics.first?.code, .unsupportedSchema)
    }

    private func makeStack(databaseURL: URL) -> MessagesDataAccessStack {
        MessagesDataAccessStack(
            configuration: MessagesStoreConfiguration(databaseURL: databaseURL, attachmentsDirectoryURL: nil),
            contactProvider: SyntheticContactProvider(),
            permissionManager: nil
        )
    }
}

private actor SyntheticContactProvider: ContactProviding, ContactResolving {
    func contacts(matching query: String, page: PageRequest) async throws -> Page<Contact> {
        let all = [
            try await contact(for: MessageHandle(rowID: 1, value: "+1 (555) 123-0001", service: .iMessage)),
            try await contact(for: MessageHandle(rowID: 2, value: "bob@example.com", service: .iMessage))
        ]
        let filtered = query.isEmpty ? all : all.filter { $0.displayName.localizedCaseInsensitiveContains(query) }

        return Page(items: filtered, hasMore: false, totalCount: filtered.count)
    }

    func contact(id: ContactID) async throws -> Contact {
        switch id.rawValue {
        case "handle:1":
            return try await contact(for: MessageHandle(rowID: 1, value: "+1 (555) 123-0001", service: .iMessage))
        case "handle:2":
            return try await contact(for: MessageHandle(rowID: 2, value: "bob@example.com", service: .iMessage))
        default:
            throw I2MessageError.notFound(resource: "Contact", id: id.rawValue)
        }
    }

    func contact(for handle: MessageHandle) async throws -> Contact {
        Contact.fallback(
            handle: ContactHandleNormalizer.contactHandle(value: handle.value, service: handle.service),
            handleRowID: handle.rowID,
            resolvedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func contacts(for handles: [MessageHandle]) async throws -> [MessageHandle: Contact] {
        var contactsByHandle: [MessageHandle: Contact] = [:]
        for handle in handles {
            contactsByHandle[handle] = try await contact(for: handle)
        }
        return contactsByHandle
    }

    func contactID(for handle: MessageHandle) async throws -> ContactID {
        try await contact(for: handle).id
    }
}
