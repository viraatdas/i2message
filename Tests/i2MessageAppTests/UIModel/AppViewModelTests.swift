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
        XCTAssertNil(model.selectedMessages.last?.replyToMessageID)
        XCTAssertEqual(model.statusBanner?.tone, .success)
    }

    func testMainComposerSendDoesNotCreateReplyAnchor() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let root = try XCTUnwrap(model.selectedMessages.first)

        model.updateDraftText("Normal composer send.")
        await model.sendCurrentDraft()

        let sent = try XCTUnwrap(model.selectedMessages.last)
        XCTAssertNil(sent.replyToMessageID)
        XCTAssertNil(model.repliedMessage(for: sent))
        XCTAssertTrue(model.visibleTranscriptMessages.contains { $0.id == sent.id })
        XCTAssertEqual(model.threadReplyCount(for: root), 0)
    }

    func testThreadFoldsRepliesAndSurfacesInPanel() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let root = try XCTUnwrap(model.selectedMessages.first)
        // Thread replies are sent only from the docked panel.
        model.openThread(rootID: root.id)
        model.threadDraftText = "first thread reply"
        await model.sendThreadReply()

        XCTAssertTrue(model.isThreadRoot(root))
        XCTAssertEqual(model.threadReplyCount(for: root), 1)

        // The reply is folded out of the main transcript…
        let reply = try XCTUnwrap(model.selectedMessages.last)
        XCTAssertFalse(model.visibleTranscriptMessages.contains { $0.id == reply.id })
        XCTAssertTrue(model.visibleTranscriptMessages.contains { $0.id == root.id })

        // …but appears in the thread panel with its root first.
        model.openThread(rootID: root.id)
        XCTAssertTrue(model.isThreadPanelPresented)
        XCTAssertEqual(model.threadPanelMessages.first?.id, root.id)
        XCTAssertTrue(model.threadPanelMessages.contains { $0.id == reply.id })
    }

    func testThreadReplyFromPanelSendsWithRootAsTarget() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let root = try XCTUnwrap(model.selectedMessages.first)
        model.openThread(rootID: root.id)
        XCTAssertFalse(model.canSendThreadReply)

        model.threadDraftText = "sent from the thread pane"
        XCTAssertTrue(model.canSendThreadReply)
        await model.sendThreadReply()

        let sent = try XCTUnwrap(model.selectedMessages.last)
        XCTAssertEqual(sent.replyToMessageID, root.id)
        XCTAssertTrue(model.threadDraftText.isEmpty)
    }

    func testLiveTailRefreshMergesNewArrivalsWithoutDroppingHistory() async throws {
        var dependencies = AppDependencies.test()
        let repository = MutableTailMessageRepository(base: dependencies.messageRepository)
        dependencies.messageRepository = repository
        dependencies.isLiveData = true
        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()

        // The initially-selected conversation is seeded from fixtures; pick a
        // different one so the transcript is served by the repository, as the
        // live app's conversations are.
        let conversationID = try XCTUnwrap(model.conversations.dropFirst().first?.id)
        await model.selectConversation(conversationID)
        XCTAssertFalse(model.selectedTranscriptState.usesFixtureData)
        await model.loadOlderMessages()
        let before = model.selectedMessages
        XCTAssertFalse(before.isEmpty)

        // No changes in the store → transcript untouched.
        await model.refreshSelectedTranscriptTail()
        XCTAssertEqual(model.selectedMessages.map(\.id), before.map(\.id))

        // A live arrival lands at the tail while loaded history is retained.
        repository.add(
            Message(
                id: MessageID(rawValue: "live-arrival"),
                conversationID: conversationID,
                senderID: nil,
                body: .text("fresh from chat.db"),
                direction: .incoming,
                service: .iMessage,
                status: .delivered,
                sentAt: Date()
            )
        )
        await model.refreshSelectedTranscriptTail()

        XCTAssertEqual(model.selectedMessages.last?.id, MessageID(rawValue: "live-arrival"))
        XCTAssertTrue(Set(model.selectedMessages.map(\.id)).isSuperset(of: Set(before.map(\.id))))
        XCTAssertEqual(model.selectedMessages.count, before.count + 1)
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

    func testReadingConversationKeepsUnreadClearedAcrossReload() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let unread = try XCTUnwrap(model.filteredConversations.first { $0.unreadCount > 0 })
        await model.selectConversation(unread.id)
        XCTAssertEqual(model.conversations.first { $0.id == unread.id }?.unreadCount, 0)

        // A live reload re-reads the (unchanged) store; the local read override
        // must keep the badge cleared.
        await model.loadConversations()
        XCTAssertEqual(model.conversations.first { $0.id == unread.id }?.unreadCount, 0)
    }

    func testGlobalSearchSurfacesContactMatchesButScopedDoesNot() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let contact = try XCTUnwrap(model.contacts.first)
        model.searchConversationScope = nil
        model.searchQuery = contact.displayName
        await model.performSearch(reset: true)
        XCTAssertTrue(model.searchContactMatches.contains { $0.id == contact.id })

        model.searchConversationScope = model.selectedConversationID
        await model.performSearch(reset: true)
        XCTAssertTrue(model.searchContactMatches.isEmpty)
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

    func testEscapeDismissesOverlaysTopmostFirst() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        // Nothing open → Esc passes through.
        XCTAssertFalse(model.dismissTopmostOverlay())

        // Thread panel under an overlay: overlay closes first, thread second.
        let root = try XCTUnwrap(model.selectedMessages.first)
        model.openThread(rootID: root.id)
        model.openCommandPalette()

        XCTAssertTrue(model.dismissTopmostOverlay())
        XCTAssertFalse(model.isCommandPalettePresented)
        XCTAssertTrue(model.isThreadPanelPresented)

        XCTAssertTrue(model.dismissTopmostOverlay())
        XCTAssertFalse(model.isThreadPanelPresented)
        XCTAssertFalse(model.dismissTopmostOverlay())

        // Each remaining overlay closes with one Esc.
        model.openNewMessage()
        XCTAssertTrue(model.dismissTopmostOverlay())
        XCTAssertFalse(model.isNewMessagePresented)

        model.isSettingsPresented = true
        XCTAssertTrue(model.dismissTopmostOverlay())
        XCTAssertFalse(model.isSettingsPresented)
    }
}

/// Wraps the fixture repository with a mutable overlay so tests can simulate
/// messages arriving in the store after the transcript was first loaded.
private final class MutableTailMessageRepository: MessageRepository, @unchecked Sendable {
    private let base: any MessageRepository
    private let lock = NSLock()
    private var extras: [ConversationID: [Message]] = [:]

    init(base: any MessageRepository) {
        self.base = base
    }

    func add(_ message: Message) {
        lock.lock()
        extras[message.conversationID, default: []].append(message)
        lock.unlock()
    }

    private func injected(for conversationID: ConversationID) -> [Message] {
        lock.lock()
        defer { lock.unlock() }
        return extras[conversationID, default: []]
    }

    func messages(
        in conversationID: ConversationID,
        page: PageRequest,
        around anchor: MessageID?
    ) async throws -> Page<Message> {
        let basePage = try await base.messages(in: conversationID, page: page, around: anchor)
        guard page.cursor == nil, anchor == nil else {
            return basePage
        }
        let injected = injected(for: conversationID)
        guard !injected.isEmpty else {
            return basePage
        }
        return Page(
            items: basePage.items + injected,
            nextCursor: basePage.nextCursor,
            previousCursor: basePage.previousCursor,
            hasMore: basePage.hasMore,
            totalCount: basePage.totalCount.map { $0 + injected.count }
        )
    }

    func message(id: MessageID) async throws -> Message {
        try await base.message(id: id)
    }

    func observeMessages(in conversationID: ConversationID) -> AsyncThrowingStream<[Message], Error> {
        base.observeMessages(in: conversationID)
    }
}
