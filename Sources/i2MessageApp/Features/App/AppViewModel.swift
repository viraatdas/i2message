import Combine
import Foundation
import SwiftUI
import i2MessageCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var sidebarDestination: SidebarDestination = .conversations
    @Published var conversationScope: ConversationScope = .all
    @Published var quickFilterText = ""
    @Published var selectedConversationID: ConversationID?
    @Published var selectedContactID: ContactID?
    @Published var highlightedMessageID: MessageID?

    @Published private(set) var conversations: [Conversation]
    @Published private(set) var contacts: [Contact]
    @Published private(set) var transcriptPages: [ConversationID: TranscriptPageState] = [:]
    @Published private(set) var conversationPhase: UIContentPhase = .loaded
    @Published private(set) var contactPhase: UIContentPhase = .loaded
    @Published private(set) var permissionSnapshot: PermissionSnapshot
    @Published private(set) var actionAvailabilitySnapshot: MessagingActionAvailabilitySnapshot
    @Published private(set) var settings: AppSettings
    @Published private(set) var indexingProgress: IndexingProgress = .idle

    @Published var searchMode: SearchMode = .exact
    @Published var searchQuery = ""
    @Published var searchConversationScope: ConversationID?
    @Published private(set) var exactSearchResults: [SearchResult] = []
    @Published private(set) var semanticSnippets: [SemanticSnippet] = []
    @Published private(set) var searchPhase: UIContentPhase = .idle
    @Published private(set) var searchHasMore = false
    @Published private(set) var searchTotalCount: Int?

    @Published var commandPaletteQuery = ""
    @Published var isCommandPalettePresented = false
    @Published var isSettingsPresented = false
    @Published private(set) var focusRequest: FocusRequest?
    @Published private(set) var statusBanner: StatusBanner?
    @Published private(set) var isOffline = false

    @Published private var draftTexts: [ConversationID: String] = [:]
    @Published private var draftAttachments: [ConversationID: [DraftAttachment]] = [:]
    @Published private(set) var sendOperation: SendOperation?

    let dependencies: AppDependencies
    private var searchPageCursor: PageCursor?
    private var observationTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var hasLoaded = false

    init(dependencies: AppDependencies = .mock()) {
        self.dependencies = dependencies
        self.conversations = dependencies.seed.conversations
        self.contacts = dependencies.seed.contacts.filter { !$0.isCurrentUser }
        self.selectedConversationID = dependencies.seed.conversations.first?.id
        self.selectedContactID = dependencies.seed.contacts.first { !$0.isCurrentUser }?.id
        self.permissionSnapshot = PermissionSnapshot(statuses: [])
        self.actionAvailabilitySnapshot = .conservativeDefault(checkedAt: Date())
        self.settings = AppSettings(pageSize: 42)
        seedInitialTranscriptPage()
    }

    deinit {
        observationTask?.cancel()
        indexingTask?.cancel()
    }

    var isUsingLiveData: Bool {
        dependencies.isLiveData
    }

    var selectedConversation: Conversation? {
        guard let selectedConversationID else {
            return filteredConversations.first
        }
        return conversations.first { $0.id == selectedConversationID }
    }

    var selectedContact: Contact? {
        guard let selectedContactID else {
            return filteredContacts.first
        }
        return contacts.first { $0.id == selectedContactID }
    }

    var selectedMessages: [Message] {
        guard let selectedConversationID else {
            return []
        }
        return transcriptPages[selectedConversationID]?.messages ?? []
    }

    var selectedTranscriptState: TranscriptPageState {
        guard let selectedConversationID else {
            return .empty
        }
        return transcriptPages[selectedConversationID] ?? .empty
    }

    var filteredConversations: [Conversation] {
        conversations
            .filter { conversation in
                switch conversationScope {
                case .all:
                    return !conversation.isArchived
                case .unread:
                    return !conversation.isArchived && conversation.unreadCount > 0
                case .pinned:
                    return !conversation.isArchived && conversation.pinnedRank != nil
                case .muted:
                    return !conversation.isArchived && conversation.isMuted
                }
            }
            .filter { conversation in
                let query = quickFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    return true
                }
                return conversation.title.localizedCaseInsensitiveContains(query)
                    || conversation.participants.contains { $0.displayName.localizedCaseInsensitiveContains(query) }
                    || (conversation.lastMessage?.text.localizedCaseInsensitiveContains(query) ?? false)
                    || dependencies.seed.messagesByConversation[conversation.id, default: []].contains {
                        $0.body.plainText.localizedCaseInsensitiveContains(query)
                            || $0.attachments.contains { $0.filename.localizedCaseInsensitiveContains(query) }
                    }
            }
            .sorted(by: MockAppDataset.conversationSort)
    }

    var filteredContacts: [Contact] {
        let query = quickFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return contacts
            .filter { contact in
                guard !query.isEmpty else {
                    return true
                }
                return contact.displayName.localizedCaseInsensitiveContains(query)
                    || contact.handles.contains { $0.value.localizedCaseInsensitiveContains(query) }
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var currentDraftText: String {
        guard let selectedConversationID else {
            return ""
        }
        return draftTexts[selectedConversationID, default: ""]
    }

    var currentDraftAttachments: [DraftAttachment] {
        guard let selectedConversationID else {
            return []
        }
        return draftAttachments[selectedConversationID, default: []]
    }

    var canSendCurrentDraft: Bool {
        !currentDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !currentDraftAttachments.isEmpty
    }

    var searchResultCountLabel: String {
        if let searchTotalCount {
            return "\(searchTotalCount)"
        }
        if searchMode == .semantic {
            return "\(semanticSnippets.count)"
        }
        return "\(exactSearchResults.count)"
    }

    var availableCommands: [AppCommand] {
        let query = commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return AppCommand.allCases
        }
        return AppCommand.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    func load() async {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        let clock = ContinuousClock()
        let start = clock.now
        AppDiagnostics.lifecycle("load_started")
        await refreshEverything()
        AppDiagnostics.loadCompleted(
            duration: start.duration(to: clock.now),
            conversations: conversations.count,
            contacts: contacts.count,
            live: dependencies.isLiveData
        )
        startObservingDataChanges()
        startBackgroundIndexingIfNeeded()
    }

    func refreshEverything() async {
        await loadSettings()
        await refreshPermissions()
        await loadConversations()
        await loadContacts()
        if let selectedConversationID, !conversations.contains(where: { $0.id == selectedConversationID }) {
            self.selectedConversationID = conversations.first?.id
            highlightedMessageID = nil
        } else if selectedConversationID == nil {
            selectedConversationID = conversations.first?.id
        }
        await loadSelectedConversation(reset: true)
    }

    func loadConversations() async {
        conversationPhase = .loading
        do {
            let page = try await dependencies.conversationRepository.conversations(
                page: PageRequest(limit: 200),
                filter: ConversationFilter(includeArchived: true)
            )
            conversations = page.items.sorted(by: MockAppDataset.conversationSort)
            conversationPhase = conversations.isEmpty ? .empty : .loaded
        } catch {
            conversationPhase = .failed(error.localizedDescription)
            AppDiagnostics.failure("load_conversations", category: String(describing: type(of: error)))
            showBanner(tone: .error, title: "Could not load conversations", message: userFacingMessage(for: error), actionTitle: "Open Settings")
        }
    }

    func loadContacts() async {
        contactPhase = .loading
        do {
            let page = try await dependencies.contactProvider.contacts(matching: "", page: PageRequest(limit: 200))
            contacts = page.items
            contactPhase = contacts.isEmpty ? .empty : .loaded
        } catch {
            contactPhase = .failed(error.localizedDescription)
            AppDiagnostics.failure("load_contacts", category: String(describing: type(of: error)))
            showBanner(tone: .error, title: "Could not load contacts", message: userFacingMessage(for: error), actionTitle: "Open Settings")
        }
    }

    func selectConversation(_ id: ConversationID, highlightedMessageID: MessageID? = nil) async {
        sidebarDestination = .conversations
        selectedConversationID = id
        self.highlightedMessageID = highlightedMessageID
        if let highlightedMessageID {
            await loadMessages(in: id, reset: true, around: highlightedMessageID)
        } else if transcriptPages[id]?.messages.isEmpty ?? true {
            await loadSelectedConversation(reset: true)
        }
    }

    func selectContact(_ id: ContactID) {
        sidebarDestination = .contacts
        selectedContactID = id
    }

    func conversations(for contact: Contact) -> [Conversation] {
        conversations
            .filter { $0.participants.contains(where: { $0.id == contact.id }) }
            .sorted(by: MockAppDataset.conversationSort)
    }

    func openConversation(with contact: Contact) async {
        if let conversation = conversations(for: contact).first {
            await selectConversation(conversation.id)
        } else {
            showBanner(
                tone: .info,
                title: "No existing thread",
                message: "Mock mode shows the contact and composer flow without creating a real Messages conversation."
            )
        }
    }

    func selectAdjacentConversation(offset: Int) async {
        let visible = filteredConversations
        guard !visible.isEmpty else {
            selectedConversationID = nil
            return
        }
        let currentIndex = selectedConversationID.flatMap { id in
            visible.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), visible.count - 1)
        await selectConversation(visible[nextIndex].id)
    }

    func loadSelectedConversation(reset: Bool) async {
        guard let selectedConversationID else {
            return
        }
        await loadMessages(in: selectedConversationID, reset: reset)
    }

    func loadOlderMessages() async {
        guard let selectedConversationID else {
            return
        }
        await loadMessages(in: selectedConversationID, reset: false)
    }

    func loadMessages(in conversationID: ConversationID, reset: Bool) async {
        await loadMessages(in: conversationID, reset: reset, around: nil)
    }

    func loadMessages(in conversationID: ConversationID, reset: Bool, around anchor: MessageID?) async {
        var state = transcriptPages[conversationID] ?? .empty
        guard reset || (state.hasMoreOlder && !state.isLoadingOlder) else {
            return
        }

        if reset {
            state.phase = .loading
        } else {
            state.isLoadingOlder = true
        }
        transcriptPages[conversationID] = state

        do {
            let page = try await dependencies.messageRepository.messages(
                in: conversationID,
                page: PageRequest(
                    cursor: reset || anchor != nil ? nil : state.olderCursor,
                    limit: max(settings.pageSize, 20),
                    direction: .older
                ),
                around: anchor
            )
            let orderedItems = page.items.sorted { $0.sentAt < $1.sentAt }
            var nextState = transcriptPages[conversationID] ?? .empty
            if reset {
                nextState.messages = orderedItems
            } else {
                let existingIDs = Set(nextState.messages.map(\.id))
                nextState.messages = orderedItems.filter { !existingIDs.contains($0.id) } + nextState.messages
            }
            nextState.olderCursor = page.nextCursor
            nextState.hasMoreOlder = page.hasMore
            nextState.totalCount = page.totalCount
            nextState.isLoadingOlder = false
            nextState.phase = nextState.messages.isEmpty ? .empty : .loaded
            nextState.errorMessage = nil
            transcriptPages[conversationID] = nextState
        } catch {
            var failedState = transcriptPages[conversationID] ?? .empty
            failedState.isLoadingOlder = false
            failedState.phase = .failed(userFacingMessage(for: error))
            failedState.errorMessage = userFacingMessage(for: error)
            transcriptPages[conversationID] = failedState
            AppDiagnostics.failure("load_transcript", category: String(describing: type(of: error)))
            showBanner(tone: .error, title: "Could not load transcript", message: userFacingMessage(for: error), actionTitle: "Open Settings")
        }
    }

    func updateDraftText(_ text: String) {
        guard let selectedConversationID else {
            return
        }
        draftTexts[selectedConversationID] = text
    }

    func addMockAttachment() {
        guard let selectedConversationID else {
            return
        }
        var attachments = draftAttachments[selectedConversationID, default: []]
        attachments.append(
            DraftAttachment(
                id: AttachmentID(rawValue: "draft.\(UUID().uuidString)"),
                fileURL: URL(fileURLWithPath: "/tmp/i2message-mock-attachment.txt"),
                filename: "Mock Attachment.txt",
                uniformTypeIdentifier: "public.plain-text"
            )
        )
        draftAttachments[selectedConversationID] = attachments
        focusRequest = .composer
    }

    func addDroppedAttachment(filename: String) {
        guard let selectedConversationID else {
            return
        }
        var attachments = draftAttachments[selectedConversationID, default: []]
        attachments.append(
            DraftAttachment(
                id: AttachmentID(rawValue: "draft.drop.\(UUID().uuidString)"),
                fileURL: URL(fileURLWithPath: "/tmp/\(filename)"),
                filename: filename,
                uniformTypeIdentifier: nil
            )
        )
        draftAttachments[selectedConversationID] = attachments
    }

    func removeDraftAttachment(_ attachment: DraftAttachment) {
        guard let selectedConversationID else {
            return
        }
        draftAttachments[selectedConversationID, default: []].removeAll { $0.id == attachment.id }
    }

    func sendCurrentDraft() async {
        guard let selectedConversationID else {
            return
        }
        let draft = MessageDraft(
            target: .existingConversation(selectedConversationID),
            text: currentDraftText,
            attachments: currentDraftAttachments,
            requestedService: selectedConversation?.service
        )

        do {
            sendOperation = try await dependencies.messageSender.validate(draft)
            let receipt = try await dependencies.messageSender.send(draft)
            AppDiagnostics.operation("send_message", state: "accepted")
            appendSentMessage(receipt: receipt, draft: draft)
            draftTexts[selectedConversationID] = ""
            draftAttachments[selectedConversationID] = []
            sendOperation = nil
            try? await dependencies.searchIndexer.invalidateIndex(for: selectedConversationID)
            if dependencies.isLiveData {
                scheduleTranscriptReload()
            }
            showBanner(
                tone: .success,
                title: dependencies.isLiveData ? "Message sent" : "Message queued",
                message: dependencies.isLiveData
                    ? "Messages.app accepted the send. The transcript will refresh from the read-only store."
                    : "Fixture send used the shared sending contract."
            )
        } catch {
            AppDiagnostics.failure("send_message", category: String(describing: type(of: error)))
            sendOperation = SendOperation(
                id: "send.failed.\(UUID().uuidString)",
                draft: draft,
                state: .failed,
                createdAt: Date(),
                updatedAt: Date(),
                failureReason: userFacingMessage(for: error)
            )
            if dependencies.isLiveData, await handoffDraftForManualSend(draft: draft) {
                return
            }
            showBanner(tone: .error, title: "Could not send", message: userFacingMessage(for: error), actionTitle: "Open Settings")
        }
    }

    func performSearch(reset: Bool = true) async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            exactSearchResults = []
            semanticSnippets = []
            searchPhase = .idle
            searchTotalCount = nil
            searchHasMore = false
            searchPageCursor = nil
            return
        }

        searchPhase = .loading
        if reset {
            searchPageCursor = nil
            exactSearchResults = []
            semanticSnippets = []
        }

        do {
            if searchMode == .semantic {
                let snippets = try await dependencies.searchProvider.semanticSearch(
                    SemanticSearchQuery(text: query, conversationID: searchConversationScope, limit: 18)
                )
                semanticSnippets = snippets
                exactSearchResults = []
                searchHasMore = false
                searchTotalCount = snippets.count
                searchPhase = snippets.isEmpty ? .empty : .loaded
            } else {
                let page = try await dependencies.searchProvider.exactSearch(
                    ExactSearchQuery(text: query, conversationID: searchConversationScope),
                    page: PageRequest(cursor: reset ? nil : searchPageCursor, limit: 18)
                )
                exactSearchResults = reset ? page.items : exactSearchResults + page.items
                searchPageCursor = page.nextCursor
                searchHasMore = page.hasMore
                searchTotalCount = page.totalCount

                if searchMode == .hybrid {
                    semanticSnippets = try await dependencies.searchProvider.semanticSearch(
                        SemanticSearchQuery(text: query, conversationID: searchConversationScope, limit: 6)
                    )
                } else {
                    semanticSnippets = []
                }
                searchPhase = exactSearchResults.isEmpty && semanticSnippets.isEmpty ? .empty : .loaded
            }
        } catch {
            AppDiagnostics.failure("search", category: String(describing: type(of: error)))
            searchPhase = .failed(userFacingMessage(for: error))
            showBanner(tone: .error, title: "Search failed", message: userFacingMessage(for: error))
        }
    }

    func loadMoreSearchResults() async {
        guard searchHasMore, searchMode != .semantic else {
            return
        }
        await performSearch(reset: false)
    }

    func openSearchResult(_ result: SearchResult) async {
        if let contactID = result.contactID, result.conversationID == nil {
            selectContact(contactID)
            return
        }

        if let conversationID = result.conversationID {
            await selectConversation(conversationID, highlightedMessageID: result.messageID)
        }
    }

    func openSemanticSnippet(_ snippet: SemanticSnippet) async {
        await selectConversation(snippet.conversationID, highlightedMessageID: snippet.sourceMessageIDs.first)
    }

    func setSearchMode(_ mode: SearchMode) async {
        searchMode = mode
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await performSearch(reset: true)
        }
    }

    func toggleSemanticSearch() async {
        await setSearchMode(searchMode == .semantic ? .exact : .semantic)
    }

    func refreshPermissions() async {
        permissionSnapshot = await dependencies.permissionManager.permissionSnapshot()
        actionAvailabilitySnapshot = await dependencies.messagingActions?.availabilitySnapshot()
            ?? .conservativeDefault(checkedAt: Date())
    }

    func requestPermission(_ permission: AppPermission) async {
        do {
            _ = try await dependencies.permissionManager.request(permission)
            await refreshPermissions()
            showBanner(tone: .success, title: "Permission updated", message: "\(permission.displayName) status refreshed.")
        } catch {
            showBanner(tone: .error, title: "Permission request failed", message: userFacingMessage(for: error), actionTitle: "Open Settings")
        }
    }

    func loadSettings() async {
        do {
            settings = try await dependencies.settingsStore.loadSettings()
        } catch {
            showBanner(tone: .warning, title: "Settings unavailable", message: error.localizedDescription)
        }
    }

    func updateSettings(_ next: AppSettings) async {
        settings = next
        do {
            try await dependencies.settingsStore.saveSettings(next)
            showBanner(tone: .success, title: "Settings saved", message: "Preferences are stored through the settings contract.")
        } catch {
            showBanner(tone: .error, title: "Could not save settings", message: error.localizedDescription)
        }
    }

    func rebuildIndexes() async {
        indexingProgress = IndexingProgress(
            isIndexing: true,
            exactProgress: 0,
            semanticProgress: 0,
            lastIndexedAt: indexingProgress.lastIndexedAt,
            message: "Preparing local index"
        )

        do {
            indexingProgress.message = "Updating exact index"
            try await dependencies.searchIndexer.rebuildExactIndex { _ in }
            indexingProgress.exactProgress = 1
            indexingProgress.message = "Refreshing semantic snippets locally"
            try await dependencies.searchIndexer.rebuildSemanticIndex { _ in }
            indexingProgress.semanticProgress = 1

            indexingProgress = IndexingProgress(
                isIndexing: false,
                exactProgress: 1,
                semanticProgress: 1,
                lastIndexedAt: Date(),
                message: "Indexes are current"
            )
            showBanner(tone: .success, title: "Indexes rebuilt", message: "Exact and semantic indexes finished locally.")
        } catch {
            indexingProgress.isIndexing = false
            showBanner(tone: .error, title: "Indexing failed", message: userFacingMessage(for: error))
        }
    }

    func toggleOfflineMode() {
        isOffline.toggle()
        if isOffline {
            showBanner(
                tone: .warning,
                title: "Offline mode",
                message: "Showing cached conversations, queued composer state, and local search surfaces."
            )
        } else {
            showBanner(tone: .success, title: "Back online", message: "Providers are reachable again.")
        }
    }

    func showMockError() {
        showBanner(
            tone: .error,
            title: "Messages database unavailable",
            message: "Full Disk Access is required before real read-only history can load.",
            actionTitle: "Open Settings"
        )
    }

    func dismissBanner() {
        statusBanner = nil
    }

    func openCommandPalette() {
        isCommandPalettePresented = true
        commandPaletteQuery = ""
        focusRequest = .commandPalette
    }

    func closeCommandPalette() {
        isCommandPalettePresented = false
        commandPaletteQuery = ""
    }

    func perform(_ command: AppCommand) async {
        switch command {
        case .newMessage:
            if dependencies.isLiveData {
                await openNewConversationHandoff()
            } else {
                sidebarDestination = .conversations
                focusRequest = .composer
                showBanner(tone: .info, title: "New message", message: "Fixture composer is ready for the selected conversation.")
            }
        case .focusFilter:
            focusRequest = .sidebarSearch
        case .openSearch:
            sidebarDestination = .search
            focusRequest = .searchField
        case .toggleSemantic:
            await toggleSemanticSearch()
        case .nextConversation:
            await selectAdjacentConversation(offset: 1)
        case .previousConversation:
            await selectAdjacentConversation(offset: -1)
        case .openSettings:
            isSettingsPresented = true
        case .rebuildIndexes:
            await rebuildIndexes()
        case .toggleOffline:
            toggleOfflineMode()
        case .simulateError:
            showMockError()
        case .clearBanner:
            dismissBanner()
        }
        closeCommandPalette()
    }

    func openSelectedConversationInMessages() async {
        guard let conversation = selectedConversation else {
            showBanner(tone: .warning, title: "No conversation selected", message: "Select a conversation before opening Messages.app.")
            return
        }

        guard let actions = dependencies.messagingActions else {
            showBanner(tone: .info, title: "Messages handoff", message: "The fixture app keeps this action local.")
            return
        }

        do {
            let result = try await actions.openConversation(
                ConversationHandoffRequest(
                    conversationID: conversation.id,
                    displayTitle: conversation.title,
                    handles: conversation.participants.flatMap(\.handles),
                    draftText: currentDraftText
                )
            )
            showBanner(tone: .success, title: "Opened Messages", message: result.userMessage)
            await refreshPermissions()
        } catch {
            showBanner(tone: .error, title: "Could not open Messages", message: userFacingMessage(for: error))
        }
    }

    func openNewConversationHandoff() async {
        guard let actions = dependencies.messagingActions else {
            sidebarDestination = .conversations
            focusRequest = .composer
            return
        }

        do {
            let result = try await actions.openConversation(
                ConversationHandoffRequest(displayTitle: "New Message")
            )
            showBanner(tone: .info, title: "New message handoff", message: result.userMessage)
            await refreshPermissions()
        } catch {
            showBanner(tone: .error, title: "Could not start handoff", message: userFacingMessage(for: error))
        }
    }

    func consumeFocusRequest(_ request: FocusRequest) {
        if focusRequest == request {
            focusRequest = nil
        }
    }

    func senderName(for id: ContactID?) -> String {
        guard let id else {
            return "System"
        }
        if id == dependencies.seed.currentUser.id {
            return "You"
        }
        if let contact = contacts.first(where: { $0.id == id }) ?? dependencies.seed.contacts.first(where: { $0.id == id }) {
            return contact.displayName
        }
        return id.rawValue == "current-user" ? "You" : "Unknown"
    }

    func contact(for id: ContactID?) -> Contact? {
        guard let id else {
            return nil
        }
        return contacts.first { $0.id == id } ?? dependencies.seed.contacts.first { $0.id == id }
    }

    func conversationTitle(for id: ConversationID) -> String {
        conversations.first { $0.id == id }?.title ?? "Conversation"
    }

    func contactNames(for conversation: Conversation) -> String {
        conversation.participants
            .filter { !$0.isCurrentUser }
            .map(\.displayName)
            .joined(separator: ", ")
    }

    private func seedInitialTranscriptPage() {
        guard let first = selectedConversationID else {
            return
        }
        let messages = dependencies.seed.messagesByConversation[first, default: []]
        let limit = max(settings.pageSize, 20)
        let start = max(0, messages.count - limit)
        transcriptPages[first] = TranscriptPageState(
            messages: Array(messages[start..<messages.count]),
            olderCursor: start > 0 ? PageCursor(rawValue: "older:\(start)") : nil,
            hasMoreOlder: start > 0,
            isLoadingOlder: false,
            phase: messages.isEmpty ? .empty : .loaded,
            totalCount: messages.count,
            errorMessage: nil
        )
    }

    private func startObservingDataChanges() {
        observationTask?.cancel()
        let repository = dependencies.conversationRepository
        let indexer = dependencies.searchIndexer
        observationTask = Task { [weak self] in
            do {
                for try await nextConversations in repository.observeConversations(filter: ConversationFilter(includeArchived: true)) {
                    try Task.checkCancellation()
                    let sorted = nextConversations.sorted(by: MockAppDataset.conversationSort)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.conversations = sorted
                        if let selectedConversationID = self.selectedConversationID,
                           !sorted.contains(where: { $0.id == selectedConversationID }) {
                            self.selectedConversationID = sorted.first?.id
                            self.highlightedMessageID = nil
                        }
                    }
                    try? await indexer.invalidateIndex(for: nil)
                    await MainActor.run { [weak self] in
                        self?.startBackgroundIndexingIfNeeded()
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run { [weak self] in
                    self?.showBanner(tone: .warning, title: "Live updates paused", message: self?.userFacingMessage(for: error) ?? "Conversation updates are unavailable.")
                }
            }
        }
    }

    private func startBackgroundIndexingIfNeeded() {
        guard settings.search.exactIndexEnabled || settings.search.semanticIndexEnabled else {
            indexingProgress = IndexingProgress(
                isIndexing: false,
                exactProgress: 0,
                semanticProgress: 0,
                lastIndexedAt: indexingProgress.lastIndexedAt,
                message: "Indexing disabled"
            )
            return
        }
        guard indexingTask == nil else {
            return
        }

        let indexer = dependencies.searchIndexer
        let exactEnabled = settings.search.exactIndexEnabled
        let semanticEnabled = settings.search.semanticIndexEnabled
        indexingTask = Task { [weak self] in
            await MainActor.run { [weak self] in
                self?.indexingProgress = IndexingProgress(
                    isIndexing: true,
                    exactProgress: exactEnabled ? 0 : 1,
                    semanticProgress: semanticEnabled ? 0 : 1,
                    lastIndexedAt: self?.indexingProgress.lastIndexedAt,
                    message: "Indexing in background"
                )
            }

            do {
                if exactEnabled {
                    try await indexer.rebuildExactIndex { _ in }
                }

                if semanticEnabled {
                    await MainActor.run { [weak self] in
                        self?.indexingProgress.exactProgress = 1
                        self?.indexingProgress.message = "Indexing semantic search"
                    }
                    try await indexer.rebuildSemanticIndex { _ in }
                }

                await MainActor.run { [weak self] in
                    self?.indexingProgress = IndexingProgress(
                        isIndexing: false,
                        exactProgress: exactEnabled ? 1 : 0,
                        semanticProgress: semanticEnabled ? 1 : 0,
                        lastIndexedAt: Date(),
                        message: "Indexes are current"
                    )
                    self?.indexingTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.indexingTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.indexingProgress.isIndexing = false
                    self?.indexingProgress.message = "Indexing paused"
                    self?.indexingTask = nil
                }
            }
        }
    }

    private func scheduleTranscriptReload() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self?.loadSelectedConversation(reset: true)
        }
    }

    private func handoffDraftForManualSend(draft: MessageDraft) async -> Bool {
        guard let actions = dependencies.messagingActions,
              case .existingConversation(let conversationID) = draft.target,
              let conversation = conversations.first(where: { $0.id == conversationID })
        else {
            return false
        }

        do {
            _ = try await actions.preparePasteHandoff(
                PasteHandoffRequest(text: draft.text, attachments: draft.attachments)
            )
            _ = try await actions.openConversation(
                ConversationHandoffRequest(
                    conversationID: conversation.id,
                    displayTitle: conversation.title,
                    handles: conversation.participants.flatMap(\.handles),
                    draftText: draft.text
                )
            )
            showBanner(
                tone: .warning,
                title: "Manual send handoff",
                message: "The draft was copied and Messages.app was opened for a user-approved send."
            )
            await refreshPermissions()
            return true
        } catch {
            return false
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }

    private func appendSentMessage(receipt: SendReceipt, draft: MessageDraft) {
        guard case .existingConversation(let conversationID) = draft.target else {
            return
        }
        let message = Message(
            id: receipt.messageID ?? MessageID(rawValue: "mock.sent.\(UUID().uuidString)"),
            conversationID: conversationID,
            senderID: dependencies.seed.currentUser.id,
            body: draft.text.isEmpty ? .empty : .text(draft.text),
            direction: .outgoing,
            service: draft.requestedService ?? selectedConversation?.service ?? .iMessage,
            status: .sent,
            sentAt: receipt.sentAt,
            attachments: draft.attachments.map {
                MessageAttachment(
                    id: $0.id,
                    kind: .file,
                    filename: $0.filename,
                    uniformTypeIdentifier: $0.uniformTypeIdentifier,
                    fileURL: $0.fileURL
                )
            },
            replyToMessageID: draft.replyToMessageID
        )

        var state = transcriptPages[conversationID] ?? .empty
        state.messages.append(message)
        state.phase = .loaded
        state.totalCount = (state.totalCount ?? state.messages.count) + 1
        transcriptPages[conversationID] = state

        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].lastMessage = LastMessagePreview(
                messageID: message.id,
                senderID: message.senderID,
                text: message.body.plainText.isEmpty ? "Attachment" : message.body.plainText,
                sentAt: message.sentAt,
                hasAttachments: !message.attachments.isEmpty
            )
            conversations[index].updatedAt = message.sentAt
            conversations.sort(by: MockAppDataset.conversationSort)
        }
        highlightedMessageID = message.id
    }

    private func showBanner(
        tone: StatusBanner.Tone,
        title: String,
        message: String,
        actionTitle: String? = nil
    ) {
        statusBanner = StatusBanner(tone: tone, title: title, message: message, actionTitle: actionTitle)
    }
}
