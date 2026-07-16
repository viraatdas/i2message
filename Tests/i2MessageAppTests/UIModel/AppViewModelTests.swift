import AppKit
import UniformTypeIdentifiers
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

    func testInitialLoadRequestsBottomScrollToNewestVisibleMessage() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let intent = try XCTUnwrap(model.transcriptScrollIntent)
        XCTAssertEqual(intent.conversationID, try XCTUnwrap(model.selectedConversationID))
        XCTAssertEqual(intent.messageID, model.visibleTranscriptMessages.last?.id)
        XCTAssertEqual(intent.anchor, .bottom)
        XCTAssertEqual(intent.reason, .initialLoad)
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
        let previousTopVisibleMessageID = try XCTUnwrap(model.visibleTranscriptMessages.first?.id)

        await model.loadOlderMessages()

        XCTAssertGreaterThan(model.selectedMessages.count, beforeCount)
        XCTAssertLessThan(try XCTUnwrap(model.selectedMessages.first?.sentAt), beforeFirst)
        let intent = try XCTUnwrap(model.transcriptScrollIntent)
        XCTAssertEqual(intent.messageID, previousTopVisibleMessageID)
        XCTAssertEqual(intent.anchor, .top)
        XCTAssertEqual(intent.reason, .olderPage)
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
        let conversationID = try XCTUnwrap(result.conversationID)
        let messageID = try XCTUnwrap(result.messageID)
        let intent = try XCTUnwrap(model.transcriptScrollIntent)
        XCTAssertEqual(intent.conversationID, conversationID)
        XCTAssertEqual(intent.messageID, messageID)
        XCTAssertEqual(intent.anchor, .center)
        XCTAssertEqual(intent.reason, .searchResult)
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
        XCTAssertNil(model.highlightedMessageID)
        let intent = try XCTUnwrap(model.transcriptScrollIntent)
        XCTAssertEqual(intent.messageID, model.selectedMessages.last?.id)
        XCTAssertEqual(intent.anchor, .bottom)
        XCTAssertEqual(intent.reason, .localSend)
        XCTAssertEqual(model.statusBanner?.tone, .success)
    }

    func testFixtureOutgoingMessageEditUpdatesTextAndKeepsHistory() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let original = try XCTUnwrap(model.selectedMessages.last {
            $0.direction == .outgoing && $0.service == .iMessage && !$0.body.plainText.isEmpty
        })
        let replacement = "Updated fixture message text"

        model.beginEditingMessage(original)
        XCTAssertEqual(model.messageEditDraft?.text, original.body.plainText)
        XCTAssertEqual(model.messageEditDraft?.editsLocally, true)

        model.updateMessageEditText(replacement)
        XCTAssertTrue(model.canCompleteMessageEdit)
        await model.completeMessageEdit()

        let updated = try XCTUnwrap(model.selectedMessages.first { $0.id == original.id })
        XCTAssertEqual(updated.body.plainText, replacement)
        XCTAssertTrue(updated.isEdited)
        XCTAssertEqual(updated.editHistory.last?.text, original.body.plainText)
        XCTAssertNil(model.messageEditDraft)
        XCTAssertEqual(model.statusBanner?.tone, .success)
    }

    func testIncomingAndNonIMessageMessagesExplainWhyTheyCannotBeEdited() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let incoming = try XCTUnwrap(model.selectedMessages.first { $0.direction == .incoming })
        model.beginEditingMessage(incoming)
        XCTAssertNil(model.messageEditDraft)
        XCTAssertEqual(model.statusBanner?.title, "Can't edit this message")
        XCTAssertTrue(model.statusBanner?.message.contains("Only messages you sent") == true)

        var sms = incoming
        sms.id = MessageID(rawValue: "test.sms.edit")
        sms.direction = .outgoing
        sms.service = .sms
        model.beginEditingMessage(sms)
        XCTAssertNil(model.messageEditDraft)
        XCTAssertTrue(model.statusBanner?.message.contains("SMS") == true)

        let mixedGroup = try XCTUnwrap(model.conversations.first {
            $0.kind == .group && $0.participants.contains(where: { participant in
                !participant.isCurrentUser && participant.handles.contains(where: { $0.service == .iMessage })
            })
        })
        sms.id = MessageID(rawValue: "test.mixed-group.edit")
        sms.conversationID = mixedGroup.id
        model.beginEditingMessage(sms)
        XCTAssertEqual(model.messageEditDraft?.message.id, sms.id)
        model.cancelMessageEdit()
    }

    func testLiveMessageEditCopiesReplacementAndOpensMessagesHandoff() async throws {
        var dependencies = AppDependencies.test()
        let actions = RecordingMessagingActions()
        dependencies.isLiveData = true
        dependencies.messagingActions = actions
        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()

        let liveConversationID = try XCTUnwrap(model.conversations.dropFirst().first?.id)
        await model.selectConversation(liveConversationID)
        XCTAssertFalse(model.selectedTranscriptState.usesFixtureData)
        let conversation = try XCTUnwrap(model.selectedConversation)
        let recentMessage = Message(
            id: MessageID(rawValue: "test.live.edit"),
            conversationID: conversation.id,
            senderID: dependencies.seed.currentUser.id,
            body: .text("Original live text"),
            direction: .outgoing,
            service: .iMessage,
            status: .sent,
            sentAt: Date().addingTimeInterval(-60)
        )

        model.beginEditingMessage(recentMessage)
        XCTAssertEqual(model.messageEditDraft?.editsLocally, false)
        model.updateMessageEditText("Corrected live text")
        await model.completeMessageEdit()

        let recorded = await actions.recordedHandoffs()
        XCTAssertEqual(recorded.paste.map(\.text), ["Corrected live text"])
        XCTAssertEqual(recorded.open.map(\.conversationID), [conversation.id])
        XCTAssertNil(model.messageEditDraft)
        XCTAssertEqual(model.statusBanner?.title, "Edited text copied")
    }

    func testLiveMessageEditRejectsExpiredWindowAndFifthPriorEdit() async throws {
        var dependencies = AppDependencies.test()
        dependencies.isLiveData = true
        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()

        let conversationID = try XCTUnwrap(model.conversations.dropFirst().first?.id)
        await model.selectConversation(conversationID)
        XCTAssertFalse(model.selectedTranscriptState.usesFixtureData)
        var message = Message(
            id: MessageID(rawValue: "test.expired.edit"),
            conversationID: conversationID,
            senderID: dependencies.seed.currentUser.id,
            body: .text("Too old"),
            direction: .outgoing,
            service: .iMessage,
            status: .sent,
            sentAt: Date().addingTimeInterval(-(15 * 60 + 1))
        )

        model.beginEditingMessage(message)
        XCTAssertNil(model.messageEditDraft)
        XCTAssertTrue(model.statusBanner?.message.contains("15-minute") == true)

        message.sentAt = Date()
        message.editHistory = (0..<5).map {
            MessageEditVersion(text: "Version \($0)", editedAt: Date().addingTimeInterval(Double($0)))
        }
        model.beginEditingMessage(message)
        XCTAssertNil(model.messageEditDraft)
        XCTAssertTrue(model.statusBanner?.message.contains("five edits") == true)
    }

    func testLiveConversationFailureCannotSendFixtureRecipient() async {
        var dependencies = AppDependencies.test()
        let sender = SlowCountingMessageSender(delayNanoseconds: 0)
        dependencies.isLiveData = true
        dependencies.seed = .empty
        dependencies.conversationRepository = ThrowingConversationRepository()
        dependencies.messageSender = sender

        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()
        model.updateDraftText("must not leave this Mac")
        await model.sendCurrentDraft()

        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertNil(model.selectedConversationID)
        let sendCount = await sender.sentCount()
        XCTAssertEqual(sendCount, 0)
    }

    func testConcurrentComposerSubmitsDraftExactlyOnce() async throws {
        var dependencies = AppDependencies.test()
        let sender = SlowCountingMessageSender(delayNanoseconds: 160_000_000)
        dependencies.messageSender = sender
        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()
        model.updateDraftText("one send only")

        let first = Task { await model.sendCurrentDraft() }
        try await Task.sleep(nanoseconds: 20_000_000)
        let second = Task { await model.sendCurrentDraft() }
        await first.value
        await second.value

        let sendCount = await sender.sentCount()
        XCTAssertEqual(sendCount, 1)
        XCTAssertEqual(model.selectedMessages.filter { $0.body.plainText == "one send only" }.count, 1)
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

        model.highlightedMessageID = reply.id
        XCTAssertTrue(model.visibleTranscriptMessages.contains { $0.id == reply.id })

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
        let previousScrollIntent = model.transcriptScrollIntent
        await model.sendThreadReply()

        let sent = try XCTUnwrap(model.selectedMessages.last)
        XCTAssertEqual(sent.replyToMessageID, root.id)
        XCTAssertTrue(model.threadDraftText.isEmpty)
        XCTAssertEqual(model.transcriptScrollIntent, previousScrollIntent)
    }

    func testChangingConversationClosesThreadPanel() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let root = try XCTUnwrap(model.selectedMessages.first)
        let nextConversation = try XCTUnwrap(model.conversations.first { $0.id != model.selectedConversationID })

        model.openThread(rootID: root.id)
        model.threadDraftText = "partial reply"

        await model.selectConversation(nextConversation.id)

        XCTAssertFalse(model.isThreadPanelPresented)
        XCTAssertNil(model.threadRootID)
        XCTAssertTrue(model.threadDraftText.isEmpty)
    }

    func testEmojiInsertionUpdatesMainAndThreadDraftsIndependently() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        model.updateDraftText("Main")
        model.insertEmojiInCurrentDraft(" 🫡 ")
        XCTAssertEqual(model.currentDraftText, "Main🫡")

        model.insertEmojiInCurrentDraft("not an emoji")
        XCTAssertEqual(model.currentDraftText, "Main🫡")

        let root = try XCTUnwrap(model.selectedMessages.first)
        model.openThread(rootID: root.id)
        model.threadDraftText = "Thread"
        model.insertEmojiInThreadDraft("🎯")

        XCTAssertEqual(model.currentDraftText, "Main🫡")
        XCTAssertEqual(model.threadDraftText, "Thread🎯")
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
        let previousScrollIntent = model.transcriptScrollIntent
        await model.refreshSelectedTranscriptTail()
        XCTAssertEqual(model.selectedMessages.map(\.id), before.map(\.id))
        XCTAssertEqual(model.transcriptScrollIntent, previousScrollIntent)

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
        XCTAssertEqual(model.transcriptScrollIntent, previousScrollIntent)
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

    func testNewMessageSubmitDoesNotUseStaleDefaultSuggestion() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()
        model.openNewMessage()
        let staleDefaultID = try XCTUnwrap(model.newMessageSuggestions.first?.id)

        model.newMessageQuery = "+1 (650) 555-9999"
        await model.submitNewMessage(selectedSuggestionID: staleDefaultID)

        let pending = try XCTUnwrap(model.pendingNewConversation)
        XCTAssertEqual(pending.handles.first?.value, "+1 (650) 555-9999")
        XCTAssertEqual(pending.handles.first?.normalizedValue, "6505559999")
    }

    func testPendingConversationSendStaysOnPendingThreadUntilRealConversationAppears() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        await model.startConversation(withHandle: "friend@example.com")
        XCTAssertNotNil(model.pendingNewConversation)

        model.updateDraftText("First hello")
        await model.sendCurrentDraft()

        XCTAssertNotNil(model.pendingNewConversation)
        XCTAssertEqual(model.selectedConversationID, AppViewModel.pendingConversationID)
        XCTAssertEqual(model.selectedMessages.last?.body.plainText, "First hello")
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

    func testCurrentUserReactionTracksTapbackPillSelection() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let target = try XCTUnwrap(model.selectedMessages.first)
        XCTAssertNil(model.currentUserReaction(on: target), "No tapback selected before the user reacts")

        model.toggleReaction(.loved, on: target)
        var updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertEqual(model.currentUserReaction(on: updated)?.kind, .loved)

        // Switching tapbacks moves the selection rather than accumulating.
        model.toggleReaction(.laughed, on: updated)
        updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertEqual(model.currentUserReaction(on: updated)?.kind, .laughed)

        // Toggling the active tapback off clears the pill selection.
        model.toggleReaction(.laughed, on: updated)
        updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertNil(model.currentUserReaction(on: updated))
    }

    func testCustomReactionUsesDisplayTextInFixturesOnly() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()

        let target = try XCTUnwrap(model.selectedMessages.first)
        let currentUserID = model.dependencies.seed.currentUser.id
        let baseline = target.reactions.count

        model.toggleCustomReaction(" 🫡 ", on: target)
        var updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertEqual(updated.reactions.count, baseline + 1)
        XCTAssertTrue(updated.reactions.contains {
            $0.kind == .custom && $0.displayText == "🫡" && $0.senderID == currentUserID
        })

        model.toggleCustomReaction("plain text", on: updated)
        updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertEqual(updated.reactions.count, baseline + 1)

        model.toggleCustomReaction("🫡", on: updated)
        updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertEqual(updated.reactions.count, baseline)
    }

    func testCustomReactionDoesNotMutateLiveTranscript() async throws {
        var dependencies = AppDependencies.test()
        dependencies.isLiveData = true
        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()

        let conversationID = try XCTUnwrap(model.conversations.dropFirst().first?.id)
        await model.selectConversation(conversationID)
        XCTAssertFalse(model.selectedTranscriptState.usesFixtureData)

        let target = try XCTUnwrap(model.selectedMessages.first)
        let baseline = target.reactions

        model.toggleCustomReaction("🫡", on: target)

        let updated = try XCTUnwrap(model.selectedMessages.first { $0.id == target.id })
        XCTAssertEqual(updated.reactions, baseline)
        XCTAssertEqual(model.statusBanner?.tone, .info)
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

    func testPasteImageWritesTempFileAndAddsDraftAttachment() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()
        _ = try XCTUnwrap(model.selectedConversationID)

        let pngData = try Self.makeSamplePNGData()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("i2message.tests.paste.image"))
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)

        let before = model.currentDraftAttachments.count
        let consumed = model.pasteImageAttachments(from: pasteboard)

        XCTAssertTrue(consumed, "An image pasteboard should be consumed as an attachment")
        XCTAssertEqual(model.currentDraftAttachments.count, before + 1)

        let attachment = try XCTUnwrap(model.currentDraftAttachments.last)
        // The DraftAttachment must point at a real on-disk temp file with the
        // correct extension and identical bytes to what was on the pasteboard.
        XCTAssertTrue(attachment.fileURL.isFileURL)
        XCTAssertEqual(attachment.fileURL.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: attachment.fileURL), pngData)
        XCTAssertEqual(attachment.uniformTypeIdentifier, UTType.png.identifier)

        try? FileManager.default.removeItem(at: attachment.fileURL)
    }

    func testPasteTextOnlyPasteboardIsNotConsumed() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()
        _ = try XCTUnwrap(model.selectedConversationID)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("i2message.tests.paste.text"))
        pasteboard.clearContents()
        pasteboard.setString("just some text", forType: .string)

        let before = model.currentDraftAttachments.count
        XCTAssertFalse(model.pasteImageAttachments(from: pasteboard))
        XCTAssertEqual(model.currentDraftAttachments.count, before)
    }

    func testSelectedAndDroppedAttachmentsKeepReadableFileURLs() async throws {
        let model = AppViewModel(dependencies: .test())
        await model.refreshEverything()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("i2message-attachment-\(UUID().uuidString).txt")
        let bytes = Data("attachment payload".utf8)
        try bytes.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(model.addDraftAttachments(fileURLs: [fileURL]), 1)
        let attachment = try XCTUnwrap(model.currentDraftAttachments.last)
        XCTAssertEqual(attachment.fileURL, fileURL.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: attachment.fileURL), bytes)

        let missing = fileURL.deletingLastPathComponent().appendingPathComponent("missing-\(UUID().uuidString)")
        XCTAssertEqual(model.addDraftAttachments(fileURLs: [missing]), 0)
        XCTAssertEqual(model.currentDraftAttachments.count, 1)
    }

    func testSearchResultLoadsConversationOutsideRecentWorkingSet() async throws {
        var dependencies = AppDependencies.test()
        let hidden = try XCTUnwrap(dependencies.seed.conversations.last)
        dependencies.conversationRepository = FilteringConversationRepository(
            base: dependencies.conversationRepository,
            hiddenID: hidden.id
        )
        dependencies.isLiveData = true
        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()
        XCTAssertFalse(model.conversations.contains { $0.id == hidden.id })

        let targetMessage = try XCTUnwrap(dependencies.seed.messagesByConversation[hidden.id]?.last)
        await model.openSearchResult(
            SearchResult(
                id: "older-hit",
                kind: .message,
                conversationID: hidden.id,
                messageID: targetMessage.id,
                title: hidden.title,
                subtitle: "",
                snippet: targetMessage.body.plainText,
                score: 1
            )
        )

        XCTAssertEqual(model.selectedConversation?.id, hidden.id)
        XCTAssertTrue(model.conversations.contains { $0.id == hidden.id })
        XCTAssertEqual(model.highlightedMessageID, targetMessage.id)
    }

    private static func makeSamplePNGData() throws -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        return try XCTUnwrap(rep?.representation(using: .png, properties: [:]))
    }

    func testAttachmentDescriptionTaskCancelsWhenModelDeinitializes() async throws {
        var dependencies = AppDependencies.test()
        let describer = CancellableImageDescriber()
        dependencies.imageDescriber = describer

        let imageMessage = try XCTUnwrap(
            dependencies.seed.allMessages
                .first { message in message.attachments.contains { $0.kind == .image } }
        )
        let imageAttachment = try XCTUnwrap(imageMessage.attachments.first { $0.kind == .image })

        var model: AppViewModel? = AppViewModel(dependencies: dependencies)
        let weakModel = WeakBox(model)

        model?.requestAttachmentDescription(for: imageAttachment, in: imageMessage)
        await describer.waitForStarts(1)

        model = nil

        XCTAssertNil(weakModel.value)
        await describer.waitForCancellations(1)
        let counts = await describer.counts()
        XCTAssertEqual(counts.cancelled, 1)
        XCTAssertEqual(counts.completed, 0)
    }

    func testContactThumbnailTaskCancelsWhenModelDeinitializes() async throws {
        var dependencies = AppDependencies.test()
        let photoProvider = CancellableContactPhotoProvider()
        dependencies.contactPhotoProvider = photoProvider

        let contact = try XCTUnwrap(dependencies.seed.contacts.first { !$0.isCurrentUser })
        var model: AppViewModel? = AppViewModel(dependencies: dependencies)
        let weakModel = WeakBox(model)

        model?.requestContactThumbnail(for: contact)
        await photoProvider.waitForStarts(1)

        model = nil

        XCTAssertNil(weakModel.value)
        await photoProvider.waitForCancellations(1)
        let counts = await photoProvider.counts()
        XCTAssertEqual(counts.cancelled, 1)
        XCTAssertEqual(counts.completed, 0)
    }

    func testConcurrentLiveTailRefreshesShareRepositoryWork() async throws {
        var dependencies = AppDependencies.test()
        let repository = CountingDelayMessageRepository(base: dependencies.messageRepository)
        dependencies.messageRepository = repository
        dependencies.isLiveData = true

        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()
        let conversationID = try XCTUnwrap(model.conversations.dropFirst().first?.id)
        await model.selectConversation(conversationID)
        XCTAssertFalse(model.selectedTranscriptState.usesFixtureData)

        repository.reset()
        let first = Task { await model.refreshSelectedTranscriptTail() }
        await repository.waitForMessageCalls(1)
        let second = Task { await model.refreshSelectedTranscriptTail() }

        await first.value
        await second.value

        XCTAssertEqual(repository.messageCallCount, 1)
    }

    func testRestartingIndexRebuildCancelsPreviousRun() async {
        var dependencies = AppDependencies.test()
        let indexer = CancellableSearchIndexer()
        dependencies.searchIndexer = indexer

        let model = AppViewModel(dependencies: dependencies)
        let first = Task { await model.rebuildIndexes() }
        await indexer.waitForStarts(1)

        let second = Task { await model.rebuildIndexes() }
        await indexer.waitForCancellations(1)

        await first.value
        await second.value

        let counts = await indexer.counts()
        XCTAssertGreaterThanOrEqual(counts.started, 2)
        XCTAssertGreaterThanOrEqual(counts.cancelled, 1)
        XCTAssertGreaterThanOrEqual(counts.completed, 1)
    }

    func testContactsPermissionGrantRestartsSearchMetadataIndexing() async {
        var dependencies = AppDependencies.test()
        let indexer = CancellableSearchIndexer()
        dependencies.searchIndexer = indexer

        let model = AppViewModel(dependencies: dependencies)
        await model.refreshEverything()
        await model.requestPermission(.contacts)
        await indexer.waitForStarts(1)

        let counts = await indexer.counts()
        XCTAssertGreaterThanOrEqual(counts.started, 1)
        XCTAssertTrue(model.indexingProgress.isIndexing)
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

private struct ThrowingConversationRepository: ConversationRepository {
    func conversations(page: PageRequest, filter: ConversationFilter) async throws -> Page<Conversation> {
        throw I2MessageError.permissionDenied(.fullDiskAccess, reason: "test denied")
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        throw I2MessageError.notFound(resource: "Conversation", id: id.rawValue)
    }

    func observeConversations(filter: ConversationFilter) -> AsyncThrowingStream<[Conversation], Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: I2MessageError.permissionDenied(.fullDiskAccess, reason: "test denied"))
        }
    }
}

private struct FilteringConversationRepository: ConversationRepository {
    let base: any ConversationRepository
    let hiddenID: ConversationID

    func conversations(page: PageRequest, filter: ConversationFilter) async throws -> Page<Conversation> {
        let page = try await base.conversations(page: page, filter: filter)
        return Page(
            items: page.items.filter { $0.id != hiddenID },
            nextCursor: page.nextCursor,
            previousCursor: page.previousCursor,
            hasMore: page.hasMore,
            totalCount: page.totalCount.map { max(0, $0 - 1) }
        )
    }

    func conversation(id: ConversationID) async throws -> Conversation {
        try await base.conversation(id: id)
    }

    func observeConversations(filter: ConversationFilter) -> AsyncThrowingStream<[Conversation], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await conversations in base.observeConversations(filter: filter) {
                        continuation.yield(conversations.filter { $0.id != hiddenID })
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private actor SlowCountingMessageSender: MessageSending {
    private let delayNanoseconds: UInt64
    private var count = 0

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func validate(_ draft: MessageDraft) async throws -> SendOperation {
        SendOperation(
            id: "slow-send",
            draft: draft,
            state: .validating,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func send(_ draft: MessageDraft) async throws -> SendReceipt {
        count += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let conversationID: ConversationID?
        if case .existingConversation(let id) = draft.target {
            conversationID = id
        } else {
            conversationID = nil
        }
        return SendReceipt(
            operationID: "slow-send",
            conversationID: conversationID,
            messageID: nil,
            sentAt: Date()
        )
    }

    func sentCount() -> Int { count }
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

private final class CountingDelayMessageRepository: MessageRepository, @unchecked Sendable {
    private let base: any MessageRepository
    private let lock = NSLock()
    private var _messageCallCount = 0

    init(base: any MessageRepository) {
        self.base = base
    }

    var messageCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _messageCallCount
    }

    func reset() {
        lock.lock()
        _messageCallCount = 0
        lock.unlock()
    }

    private func incrementMessageCallCount() {
        lock.lock()
        _messageCallCount += 1
        lock.unlock()
    }

    func waitForMessageCalls(_ expectedCount: Int) async {
        for _ in 0..<100 {
            if messageCallCount >= expectedCount {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func messages(
        in conversationID: ConversationID,
        page: PageRequest,
        around anchor: MessageID?
    ) async throws -> Page<Message> {
        incrementMessageCallCount()
        try await Task.sleep(nanoseconds: 120_000_000)
        return try await base.messages(in: conversationID, page: page, around: anchor)
    }

    func message(id: MessageID) async throws -> Message {
        try await base.message(id: id)
    }

    func observeMessages(in conversationID: ConversationID) -> AsyncThrowingStream<[Message], Error> {
        base.observeMessages(in: conversationID)
    }
}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

private actor CancellableImageDescriber: ImageDescribing {
    private var started = 0
    private var cancelled = 0
    private var completed = 0

    func describe(_ attachment: MessageAttachment) async -> String? {
        started += 1
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            completed += 1
            return "late image description"
        } catch is CancellationError {
            cancelled += 1
            return nil
        } catch {
            return nil
        }
    }

    func waitForStarts(_ expectedCount: Int) async {
        for _ in 0..<100 {
            if started >= expectedCount {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func waitForCancellations(_ expectedCount: Int) async {
        for _ in 0..<100 {
            if cancelled >= expectedCount {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func counts() -> (started: Int, cancelled: Int, completed: Int) {
        (started, cancelled, completed)
    }
}

private actor CancellableContactPhotoProvider: ContactPhotoProviding {
    private var started = 0
    private var cancelled = 0
    private var completed = 0

    func thumbnailData(for contactID: ContactID) async throws -> Data? {
        started += 1
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            completed += 1
            return Data([0x1])
        } catch is CancellationError {
            cancelled += 1
            throw CancellationError()
        } catch {
            throw error
        }
    }

    func waitForStarts(_ expectedCount: Int) async {
        for _ in 0..<100 {
            if started >= expectedCount {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func waitForCancellations(_ expectedCount: Int) async {
        for _ in 0..<100 {
            if cancelled >= expectedCount {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func counts() -> (started: Int, cancelled: Int, completed: Int) {
        (started, cancelled, completed)
    }
}

private actor CancellableSearchIndexer: SearchIndexing {
    private var started = 0
    private var cancelled = 0
    private var completed = 0

    func rebuildExactIndex(progress: @Sendable @escaping (Double) -> Void) async throws {
        try await rebuild(progress: progress)
    }

    func rebuildSemanticIndex(progress: @Sendable @escaping (Double) -> Void) async throws {
        try await rebuild(progress: progress)
    }

    func invalidateIndex(for conversationID: ConversationID?) async throws {}

    private func rebuild(progress: @Sendable @escaping (Double) -> Void) async throws {
        started += 1
        progress(0)
        do {
            try await Task.sleep(nanoseconds: 220_000_000)
            progress(1)
            completed += 1
        } catch is CancellationError {
            cancelled += 1
            throw CancellationError()
        } catch {
            throw error
        }
    }

    func waitForStarts(_ expectedCount: Int) async {
        for _ in 0..<100 {
            if started >= expectedCount {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func waitForCancellations(_ expectedCount: Int) async {
        for _ in 0..<100 {
            if cancelled >= expectedCount {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func counts() -> (started: Int, cancelled: Int, completed: Int) {
        (started, cancelled, completed)
    }
}

private actor RecordingMessagingActions: MessagingActionServicing {
    private var pasteRequests: [PasteHandoffRequest] = []
    private var openRequests: [ConversationHandoffRequest] = []

    func availabilitySnapshot() async -> MessagingActionAvailabilitySnapshot {
        .conservativeDefault(checkedAt: Date())
    }

    func validate(_ draft: MessageDraft) async throws -> SendOperation {
        SendOperation(
            id: "recording.validate",
            draft: draft,
            state: .validating,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func send(_ draft: MessageDraft) async throws -> SendReceipt {
        let conversationID: ConversationID?
        if case .existingConversation(let id) = draft.target {
            conversationID = id
        } else {
            conversationID = nil
        }
        return SendReceipt(
            operationID: "recording.send",
            conversationID: conversationID,
            messageID: nil,
            sentAt: Date()
        )
    }

    func startConversation(_ draft: MessageDraft) async throws -> SendReceipt {
        try await send(draft)
    }

    func reply(_ draft: MessageDraft, to messageID: MessageID) async throws -> SendReceipt {
        try await send(draft)
    }

    func openConversation(_ request: ConversationHandoffRequest) async throws -> MessagingActionResult {
        openRequests.append(request)
        return result(kind: .openInMessages, outcome: .handedOff)
    }

    func handoffContact(_ request: ContactHandoffRequest) async throws -> MessagingActionResult {
        result(kind: .contactHandoff, outcome: .handedOff)
    }

    func preparePasteHandoff(_ request: PasteHandoffRequest) async throws -> MessagingActionResult {
        pasteRequests.append(request)
        return result(kind: .pasteHandoff, outcome: .completed)
    }

    func dragItems(for request: DragHandoffRequest) async throws -> [MessagingHandoffItem] {
        []
    }

    func markRead(_ request: MarkReadRequest) async throws -> MessagingActionResult {
        result(kind: .markRead, outcome: .completed)
    }

    func recordedHandoffs() -> (paste: [PasteHandoffRequest], open: [ConversationHandoffRequest]) {
        (pasteRequests, openRequests)
    }

    private func result(kind: MessagingActionKind, outcome: MessagingActionOutcome) -> MessagingActionResult {
        MessagingActionResult(
            id: "recording.\(kind.rawValue)",
            kind: kind,
            outcome: outcome,
            completedAt: Date(),
            userMessage: "Recorded test action."
        )
    }
}
