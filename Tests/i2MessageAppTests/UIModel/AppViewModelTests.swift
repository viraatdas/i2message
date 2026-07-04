import XCTest
@testable import i2Message
import i2MessageCore

@MainActor
final class AppViewModelTests: XCTestCase {
    func testInitialLoadHydratesConversationsContactsAndTranscript() async {
        let model = AppViewModel(dependencies: .test())

        await model.refreshEverything()

        XCTAssertFalse(model.filteredConversations.isEmpty)
        XCTAssertFalse(model.filteredContacts.isEmpty)
        XCTAssertNotNil(model.selectedConversation)
        XCTAssertFalse(model.selectedMessages.isEmpty)
        XCTAssertTrue(model.selectedTranscriptState.hasMoreOlder)
    }

    func testConversationScopesAndQuickFilter() async {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        model.conversationScope = .unread
        XCTAssertTrue(model.filteredConversations.allSatisfy { $0.unreadCount > 0 })

        model.conversationScope = .pinned
        XCTAssertTrue(model.filteredConversations.allSatisfy { $0.pinnedRank != nil })

        model.conversationScope = .all
        model.quickFilterText = "semantic"
        XCTAssertTrue(model.filteredConversations.contains { $0.title == "Search indexing" })
    }

    func testTranscriptPaginationPrependsOlderMessages() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let beforeCount = model.selectedMessages.count
        let beforeFirst = try XCTUnwrap(model.selectedMessages.first?.sentAt)

        await model.loadOlderMessages()

        XCTAssertGreaterThan(model.selectedMessages.count, beforeCount)
        XCTAssertLessThan(try XCTUnwrap(model.selectedMessages.first?.sentAt), beforeFirst)
    }

    func testExactSearchPagesAndOpensResult() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        model.sidebarDestination = .search
        model.searchQuery = "semantic"
        model.searchMode = .exact
        await model.performSearch(reset: true)

        XCTAssertEqual(model.searchPhase, .loaded)
        XCTAssertFalse(model.exactSearchResults.isEmpty)

        let countAfterFirstPage = model.exactSearchResults.count
        if model.searchHasMore {
            await model.loadMoreSearchResults()
            XCTAssertGreaterThan(model.exactSearchResults.count, countAfterFirstPage)
        }

        let result = try XCTUnwrap(model.exactSearchResults.first { $0.conversationID != nil })
        await model.openSearchResult(result)

        XCTAssertEqual(model.sidebarDestination, .conversations)
        XCTAssertEqual(model.selectedConversationID, result.conversationID)
    }

    func testSemanticSearchReturnsLocalSnippets() async {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        model.searchQuery = "local privacy embeddings"
        model.searchMode = .semantic
        await model.performSearch(reset: true)

        XCTAssertEqual(model.searchPhase, .loaded)
        XCTAssertFalse(model.semanticSnippets.isEmpty)
        XCTAssertTrue(model.semanticSnippets.allSatisfy { $0.embeddingModelIdentifier.contains("local") })
    }

    func testComposerValidationAndMockSend() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        await model.sendCurrentDraft()
        XCTAssertEqual(model.statusBanner?.tone, .error)

        model.updateDraftText("This is a mock send.")
        let beforeCount = model.selectedMessages.count
        await model.sendCurrentDraft()

        XCTAssertEqual(model.currentDraftText, "")
        XCTAssertGreaterThan(model.selectedMessages.count, beforeCount)
        XCTAssertEqual(model.selectedMessages.last?.body.plainText, "This is a mock send.")
        XCTAssertEqual(model.statusBanner?.tone, .success)
    }

    func testCommandPaletteFiltersAndRunsCommands() async {
        let model = AppViewModel(dependencies: .test())

        model.openCommandPalette()
        model.commandPaletteQuery = "offline"

        XCTAssertEqual(model.availableCommands, [.toggleOffline])

        await model.perform(.toggleOffline)

        XCTAssertTrue(model.isOffline)
        XCTAssertFalse(model.isCommandPalettePresented)
    }
}
