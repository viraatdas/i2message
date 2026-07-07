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

    func testReplyDraftSendsWithReplyContext() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let target = try XCTUnwrap(model.selectedMessages.first)
        model.beginReply(to: target)
        XCTAssertEqual(model.currentReplyTarget?.id, target.id)
        XCTAssertEqual(model.focusRequest, .composer)

        model.updateDraftText("Replying to the first message.")
        await model.sendCurrentDraft()

        let sent = try XCTUnwrap(model.selectedMessages.last)
        XCTAssertEqual(sent.replyToMessageID, target.id)
        XCTAssertEqual(model.repliedMessage(for: sent)?.id, target.id)
        XCTAssertNil(model.currentReplyTarget)
    }

    func testCancelReplyClearsTarget() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let target = try XCTUnwrap(model.selectedMessages.first)
        model.beginReply(to: target)
        model.cancelReply()

        XCTAssertNil(model.currentReplyTarget)
    }

    func testNewMessageStagesPendingConversationForRawHandle() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        model.openNewMessage()
        XCTAssertTrue(model.isNewMessagePresented)
        XCTAssertEqual(model.focusRequest, .newMessageRecipient)

        await model.startConversation(withHandle: "+15551234567")

        XCTAssertFalse(model.isNewMessagePresented)
        let pending = try XCTUnwrap(model.pendingNewConversation)
        XCTAssertEqual(pending.handles.first?.value, "+15551234567")
        XCTAssertEqual(model.selectedConversation?.id, AppViewModel.pendingConversationID)
        XCTAssertEqual(model.selectedConversation?.title, "+15551234567")
        XCTAssertTrue(model.selectedMessages.isEmpty)
    }

    func testPendingConversationSendClearsStagingAndReloads() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        await model.startConversation(withHandle: "friend@example.com")
        XCTAssertNotNil(model.pendingNewConversation)

        model.updateDraftText("First hello")
        await model.sendCurrentDraft()

        XCTAssertNil(model.pendingNewConversation)
        XCTAssertNotEqual(model.selectedConversationID, AppViewModel.pendingConversationID)
        XCTAssertNil(model.transcriptPages[AppViewModel.pendingConversationID])
    }

    func testDateMentionDetectionAndCalendarAdd() async throws {
        let dependencies = AppDependencies.test()
        let calendar = try XCTUnwrap(dependencies.calendarWriter as? MockCalendarWriter)
        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()

        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let futureText = "Let's meet next Friday at 3pm to review"
        let message = Message(
            id: MessageID(rawValue: "calendar.test.message"),
            conversationID: conversationID,
            senderID: nil,
            body: .text(futureText),
            direction: .incoming,
            service: .iMessage,
            status: .delivered,
            sentAt: Date()
        )

        let mention = try XCTUnwrap(model.dateMention(in: message))
        XCTAssertTrue(mention.hasTime)

        await model.addToCalendar(from: message)
        XCTAssertEqual(calendar.savedTitles.count, 1)
        XCTAssertEqual(model.statusBanner?.tone, .success)
    }

    func testPastDateMentionsAreIgnored() {
        let model = AppViewModel(dependencies: .test())
        let message = Message(
            id: MessageID(rawValue: "calendar.past.message"),
            conversationID: ConversationID(rawValue: "c"),
            senderID: nil,
            body: .text("we talked about this back on January 3, 2019"),
            direction: .incoming,
            service: .iMessage,
            status: .delivered,
            sentAt: Date()
        )
        XCTAssertNil(model.dateMention(in: message))
    }

    func testInfoPanelCollectsSharedMediaAndLinks() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let expectedMedia = model.dependencies.seed.messagesByConversation[conversationID, default: []]
            .flatMap(\.attachments)
            .filter { $0.kind == .image || $0.kind == .video }

        await model.openInfoPanel()

        XCTAssertTrue(model.isInfoPanelPresented)
        XCTAssertNotEqual(model.infoPanelPhase, .loading)
        XCTAssertEqual(model.infoPanelMedia.count, expectedMedia.count)
    }

    func testToggleReactionAddsAndRemovesTapback() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let target = try XCTUnwrap(model.selectedMessages.first)
        let currentUserID = model.dependencies.seed.currentUser.id
        let baseline = target.reactions.count

        model.toggleReaction(.loved, on: target)
        var updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertEqual(updated.reactions.count, baseline + 1)
        XCTAssertTrue(updated.reactions.contains { $0.kind == .loved && $0.senderID == currentUserID })

        // Switching to a different tapback replaces the current user's reaction.
        model.toggleReaction(.laughed, on: updated)
        updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertEqual(updated.reactions.count, baseline + 1)
        XCTAssertTrue(updated.reactions.contains { $0.kind == .laughed && $0.senderID == currentUserID })

        model.toggleReaction(.laughed, on: updated)
        updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertEqual(updated.reactions.count, baseline)
    }

    func testSearchCommandsScopeCorrectly() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()
        let selectedID = try XCTUnwrap(model.selectedConversationID)

        await model.perform(.searchCurrentChat)
        XCTAssertTrue(model.isSearchOverlayPresented)
        XCTAssertEqual(model.searchConversationScope, selectedID)
        XCTAssertEqual(model.focusRequest, .searchField)

        await model.perform(.openSearch)
        XCTAssertNil(model.searchConversationScope)
        XCTAssertTrue(model.isSearchOverlayPresented)

        model.searchQuery = "semantic"
        await model.performSearch(reset: true)
        let result = try XCTUnwrap(model.exactSearchResults.first { $0.conversationID != nil })
        await model.openSearchResult(result)
        XCTAssertFalse(model.isSearchOverlayPresented)
    }

    func testImageAttachmentsGetLocalDescriptions() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let imageMessage = try XCTUnwrap(
            model.dependencies.seed.allMessages
                .first { message in message.attachments.contains { $0.kind == .image } }
        )
        let imageAttachment = try XCTUnwrap(imageMessage.attachments.first { $0.kind == .image })

        model.requestAttachmentDescription(for: imageAttachment, in: imageMessage)
        for _ in 0..<50 where model.attachmentDescriptions[imageAttachment.id] == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let description = try XCTUnwrap(model.attachmentDescriptions[imageAttachment.id])
        XCTAssertFalse(description.isEmpty)
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
