import XCTest
@testable import i2MessageCore

final class MessagesDataAccessPerformanceTests: XCTestCase {
    func testLargeSyntheticConversationPageFetchIsBounded() async throws {
        let databaseURL = try SyntheticMessagesDatabase.makeLargeDatabase(
            conversationCount: 160,
            messagesPerConversation: 50
        )
        let stack = MessagesDataAccessStack(
            configuration: MessagesStoreConfiguration(databaseURL: databaseURL, attachmentsDirectoryURL: nil),
            contactProvider: LargeSyntheticContactProvider(),
            permissionManager: nil
        )

        let startedAt = ContinuousClock.now
        let page = try await stack.conversations.conversations(
            page: PageRequest(limit: 30),
            filter: ConversationFilter()
        )
        let elapsed = startedAt.duration(to: .now)

        XCTAssertEqual(page.items.count, 30)
        XCTAssertTrue(page.hasMore)
        XCTAssertLessThan(elapsed.components.seconds, 2)
    }

    func testLargeSyntheticTranscriptPageFetchIsBounded() async throws {
        let databaseURL = try SyntheticMessagesDatabase.makeLargeDatabase(
            conversationCount: 20,
            messagesPerConversation: 300
        )
        let stack = MessagesDataAccessStack(
            configuration: MessagesStoreConfiguration(databaseURL: databaseURL, attachmentsDirectoryURL: nil),
            contactProvider: LargeSyntheticContactProvider(),
            permissionManager: nil
        )

        let startedAt = ContinuousClock.now
        let page = try await stack.messages.messages(
            in: ConversationID(rawValue: "chat:20"),
            page: PageRequest(limit: 50),
            around: nil
        )
        let elapsed = startedAt.duration(to: .now)

        XCTAssertEqual(page.items.count, 50)
        XCTAssertTrue(page.hasMore)
        XCTAssertLessThan(elapsed.components.seconds, 2)
    }
}

private actor LargeSyntheticContactProvider: ContactProviding, ContactResolving {
    func contacts(matching query: String, page: PageRequest) async throws -> Page<Contact> {
        Page(items: [], hasMore: false, totalCount: 0)
    }

    func contact(id: ContactID) async throws -> Contact {
        throw I2MessageError.notFound(resource: "Contact", id: id.rawValue)
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
