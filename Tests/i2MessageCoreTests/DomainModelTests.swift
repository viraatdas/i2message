import XCTest
@testable import i2MessageCore

final class DomainModelTests: XCTestCase {
    func testIdentifierStringLiteralRoundTrip() throws {
        let id: ConversationID = "conversation.test"
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(ConversationID.self, from: data)

        XCTAssertEqual(decoded.rawValue, "conversation.test")
        XCTAssertEqual(decoded, id)
    }

    func testPageCarriesCursorMetadata() {
        let page = Page(
            items: MockData.conversations,
            nextCursor: PageCursor(rawValue: "older:3"),
            previousCursor: nil,
            hasMore: true,
            totalCount: 24
        )

        XCTAssertEqual(page.items.count, 3)
        XCTAssertEqual(page.nextCursor?.rawValue, "older:3")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.totalCount, 24)
    }

    func testMockConversationsHaveMessagesAndParticipants() {
        XCTAssertFalse(MockData.conversations.isEmpty)

        for conversation in MockData.conversations {
            XCTAssertFalse(conversation.title.isEmpty)
            XCTAssertFalse(conversation.participants.isEmpty)
            XCTAssertFalse(MockData.messages(for: conversation.id).isEmpty)
        }
    }

    func testSearchResultCanRepresentMessageHit() throws {
        let message = try XCTUnwrap(MockData.allMessages.first)
        let result = SearchResult(
            id: "result.\(message.id.rawValue)",
            kind: .message,
            conversationID: message.conversationID,
            messageID: message.id,
            title: "Thread",
            subtitle: "Sender",
            snippet: message.body.plainText,
            matchedRanges: [TextRange(location: 0, length: 4)],
            score: 1,
            date: message.sentAt
        )

        XCTAssertEqual(result.kind, .message)
        XCTAssertEqual(result.messageID, message.id)
        XCTAssertEqual(result.matchedRanges.first?.length, 4)
    }

    func testMutationErrorsAreExplicit() {
        let error = I2MessageError.unsupportedMutation(reason: "Direct chat.db writes are forbidden")

        XCTAssertEqual(
            error.errorDescription,
            "Unsupported Messages mutation: Direct chat.db writes are forbidden"
        )
    }

    func testDefaultPrivacySettingsKeepSemanticSearchLocal() {
        let settings = AppSettings()

        XCTAssertTrue(settings.search.exactIndexEnabled)
        XCTAssertTrue(settings.search.semanticIndexEnabled)
        XCTAssertFalse(settings.privacy.allowExternalEmbeddingProviders)
        XCTAssertTrue(settings.privacy.redactLogs)
    }
}
