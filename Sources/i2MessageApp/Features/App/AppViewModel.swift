import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import i2MessageCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var sidebarDestination: SidebarDestination = .conversations
    @Published var sidebarMode: SidebarDisplayMode = .full
    @Published var conversationScope: ConversationScope = .all
    @Published var quickFilterText = ""
    @Published var selectedConversationID: ConversationID?
    @Published var selectedContactID: ContactID?
    @Published var highlightedMessageID: MessageID?
    @Published private(set) var transcriptScrollIntent: TranscriptScrollIntent?

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
    @Published private(set) var searchContactMatches: [Contact] = []
    @Published private(set) var searchPhase: UIContentPhase = .idle
    @Published private(set) var searchHasMore = false
    @Published private(set) var searchTotalCount: Int?

    @Published var commandPaletteQuery = ""
    @Published var isCommandPalettePresented = false
    @Published var isSearchOverlayPresented = false
    @Published var isReminderPresented = false
    @Published var isOnboardingPresented = false

    @Published var isNewMessagePresented = false
    @Published var newMessageQuery = ""
    @Published private(set) var newMessageSuggestions: [Contact] = []
    @Published private(set) var pendingNewConversation: PendingNewConversation?

    /// Slack-style thread pane: when a message with replies is opened, this
    /// docks the parent + its replies on the right of the transcript.
    @Published var isThreadPanelPresented = false
    @Published var threadRootID: MessageID?
    @Published var threadDraftText = ""
    /// Reply count each thread was last seen at, so new replies can surface a
    /// quiet "new activity" dot instead of a full message in the main chat.
    @Published private var threadSeenReplyCount: [MessageID: Int] = [:]

    @Published var isInfoPanelPresented = false
    @Published private(set) var infoPanelPhase: UIContentPhase = .idle
    @Published private(set) var infoPanelMedia: [MessageAttachment] = []
    @Published private(set) var infoPanelLinks: [SharedLink] = []
    private var infoPanelConversationID: ConversationID?

    private var locallyUnreadIDs: Set<ConversationID> = []
    private var locallyReadIDs: Set<ConversationID> = []
    @Published var isSettingsPresented = false
    @Published var messageEditDraft: MessageEditDraft?
    @Published private(set) var isCompletingMessageEdit = false
    @Published private(set) var focusRequest: FocusRequest?
    @Published private(set) var statusBanner: StatusBanner?
    private var bannerDismissTask: Task<Void, Never>?
    @Published private(set) var isOffline = false

    @Published private var draftTexts: [ConversationID: String] = [:]
    @Published private var draftAttachments: [ConversationID: [DraftAttachment]] = [:]
    @Published private(set) var sendOperation: SendOperation?
    @Published private(set) var isSendingCurrentDraft = false
    @Published private(set) var isSendingThreadReply = false
    @Published private(set) var attachmentDescriptions: [AttachmentID: String] = [:]
    private var attachmentDescriptionTasks: [AttachmentID: Task<Void, Never>] = [:]
    private var attachmentDescriptionAccessOrder: [AttachmentID] = []
    @Published private(set) var contactThumbnails: [ContactID: Data] = [:]
    private var contactThumbnailTasks: [ContactID: Task<Void, Never>] = [:]
    private var contactThumbnailMisses: Set<ContactID> = []
    private var contactThumbnailAccessOrder: [ContactID] = []

    let dependencies: AppDependencies
    private var searchPageCursor: PageCursor?
    private var observationTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var backgroundIndexingDebounceTask: Task<Void, Never>?
    private var indexingTaskGeneration = 0
    private var transcriptReloadTask: Task<Void, Never>?
    private var transcriptReloadSequence = 0
    private var selectionLoadTask: Task<Void, Never>?
    private var transcriptPageAccessOrder: [ConversationID] = []
    private var refreshingTranscriptTailConversationIDs: Set<ConversationID> = []
    private var transcriptScrollSequence = 0
    private var hasLoaded = false

    private static let maxAttachmentDescriptionCacheSize = 160
    private static let maxContactThumbnailCacheSize = 200
    private static let maxDateMentionCacheSize = 500
    private static let maxTranscriptPageCacheSize = 12

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
        backgroundIndexingDebounceTask?.cancel()
        selectionLoadTask?.cancel()
        transcriptReloadTask?.cancel()
        bannerDismissTask?.cancel()
        attachmentDescriptionTasks.values.forEach { $0.cancel() }
        contactThumbnailTasks.values.forEach { $0.cancel() }
    }

    var isUsingLiveData: Bool {
        dependencies.isLiveData
    }

    var selectedConversation: Conversation? {
        if let pending = pendingNewConversation, selectedConversationID == pending.conversation.id {
            return pending.conversation
        }
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
            .sorted { lhs, rhs in
                let lhsDate = lastContactedAt(for: lhs) ?? .distantPast
                let rhsDate = lastContactedAt(for: rhs) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
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
        !isSendingCurrentDraft
            && (!currentDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !currentDraftAttachments.isEmpty)
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
        guard !Task.isCancelled else {
            return
        }
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
        let previousSelectedConversationID = selectedConversationID
        if let selectedConversationID, !conversations.contains(where: { $0.id == selectedConversationID }) {
            self.selectedConversationID = conversations.first?.id
            highlightedMessageID = nil
        } else if selectedConversationID == nil {
            selectedConversationID = conversations.first?.id
        }
        if previousSelectedConversationID != selectedConversationID {
            closeThread()
        }
        // The conversation on screen is being read; clear its badge like an
        // explicit selection would.
        if let selectedConversationID {
            markConversationRead(selectedConversationID)
        }
        await loadSelectedConversation(reset: true)
    }

    func loadConversations() async {
        conversationPhase = .loading
        do {
            // Keep a useful recent working set while older threads remain
            // reachable through exact search and direct repository lookup.
            let page = try await dependencies.conversationRepository.conversations(
                page: PageRequest(limit: dependencies.isLiveData ? 80 : 200),
                filter: ConversationFilter(includeArchived: false)
            )
            conversations = page.items.sorted(by: MockAppDataset.conversationSort)
            applyLocalUnreadOverrides()
            applyLocalReadOverrides()
            conversationPhase = conversations.isEmpty ? .empty : .loaded
        } catch {
            AppDiagnostics.failure("load_conversations", category: String(describing: type(of: error)))
            if !dependencies.seed.conversations.isEmpty {
                conversations = dependencies.seed.conversations.sorted(by: MockAppDataset.conversationSort)
                conversationPhase = .loaded
                showBanner(
                    tone: .warning,
                    title: "Showing sample conversations",
                    message: "\(userFacingMessage(for: error)) Your real conversations will appear once access is granted.",
                    actionTitle: "Open Settings"
                )
            } else {
                conversationPhase = .failed(error.localizedDescription)
                showBanner(tone: .error, title: "Could not load conversations", message: userFacingMessage(for: error), actionTitle: "Open Settings")
            }
        }
    }

    func loadContacts() async {
        if dependencies.isLiveData,
           permissionSnapshot.status(for: .contacts)?.state != .granted {
            contacts = []
            selectedContactID = nil
            contactPhase = .empty
            return
        }

        contactPhase = .loading
        do {
            let page = try await dependencies.contactProvider.contacts(matching: "", page: PageRequest(limit: 200))
            contacts = page.items
            if let selectedContactID, !contacts.contains(where: { $0.id == selectedContactID }) {
                self.selectedContactID = contacts.first?.id
            } else if selectedContactID == nil {
                selectedContactID = contacts.first?.id
            }
            contactPhase = contacts.isEmpty ? .empty : .loaded
        } catch {
            contactPhase = .failed(error.localizedDescription)
            AppDiagnostics.failure("load_contacts", category: String(describing: type(of: error)))
            showBanner(tone: .error, title: "Could not load contacts", message: userFacingMessage(for: error), actionTitle: "Open Settings")
        }
    }

    func selectConversation(_ id: ConversationID, highlightedMessageID: MessageID? = nil) async {
        sidebarDestination = .conversations
        if let pending = pendingNewConversation, pending.conversation.id != id {
            pendingNewConversation = nil
        }
        let isChangingConversation = selectedConversationID != id
        if isChangingConversation {
            closeThread()
        }
        // A previous conversation's transcript load may still be in flight; it
        // must not land after the user has already moved on, or it clobbers the
        // now-selected chat's state and stalls the switch.
        selectionLoadTask?.cancel()
        if !conversations.contains(where: { $0.id == id }),
           let resolved = try? await dependencies.conversationRepository.conversation(id: id) {
            conversations.append(resolved)
            conversations.sort(by: MockAppDataset.conversationSort)
        }
        selectedConversationID = id
        markConversationRead(id)
        touchTranscriptPage(id)
        self.highlightedMessageID = highlightedMessageID

        let task = Task { [weak self] in
            guard let self else { return }
            if let highlightedMessageID {
                await self.loadMessages(in: id, reset: true, around: highlightedMessageID)
            } else if self.transcriptPages[id]?.messages.isEmpty ?? true {
                await self.loadSelectedConversation(reset: true)
            } else if isChangingConversation, let messages = self.transcriptPages[id]?.messages {
                self.requestTranscriptTailScroll(conversationID: id, reason: .initialLoad, messages: messages)
            }
        }
        selectionLoadTask = task
        await task.value
    }

    /// Marks a conversation as most-recently-used and evicts the transcripts of
    /// chats not touched in a while. Without this the per-conversation message
    /// arrays accumulate for the whole session and memory climbs with every
    /// distinct chat opened.
    private func touchTranscriptPage(_ id: ConversationID) {
        transcriptPageAccessOrder.removeAll { $0 == id }
        transcriptPageAccessOrder.append(id)

        while transcriptPageAccessOrder.count > Self.maxTranscriptPageCacheSize {
            guard let victimIndex = transcriptPageAccessOrder.firstIndex(where: {
                $0 != selectedConversationID && $0 != Self.pendingConversationID
            }) else {
                break
            }
            let victim = transcriptPageAccessOrder.remove(at: victimIndex)
            transcriptPages[victim] = nil
        }
    }

    func selectContact(_ id: ContactID) {
        sidebarDestination = .contacts
        selectedContactID = id
        closeThread()
    }

    func cycleSidebarMode() {
        sidebarMode = sidebarMode.next
    }

    /// Cmd+U: keep the current chat visibly unread, then move on to the next
    /// one in the list. The unread mark is app-local; the Messages database
    /// stays untouched.
    func markSelectedUnreadAndAdvance() async {
        guard let selectedConversationID else {
            return
        }
        locallyReadIDs.remove(selectedConversationID)
        locallyUnreadIDs.insert(selectedConversationID)
        applyLocalUnreadOverrides()

        // Only move if there is a next chat; re-selecting the same one would
        // immediately clear the unread mark we just set.
        let visible = filteredConversations
        if let currentIndex = visible.firstIndex(where: { $0.id == selectedConversationID }),
           currentIndex + 1 < visible.count {
            await selectConversation(visible[currentIndex + 1].id)
        }
    }

    private func applyLocalUnreadOverrides() {
        for index in conversations.indices where locallyUnreadIDs.contains(conversations[index].id) {
            conversations[index].unreadCount = max(1, conversations[index].unreadCount)
        }
    }

    /// Reading a chat marks it read locally. The Messages database is read-only,
    /// so this override is what keeps the badge cleared across live reloads.
    private func applyLocalReadOverrides() {
        for index in conversations.indices where locallyReadIDs.contains(conversations[index].id) {
            conversations[index].unreadCount = 0
        }
    }

    private func markConversationRead(_ conversationID: ConversationID) {
        locallyUnreadIDs.remove(conversationID)
        locallyReadIDs.insert(conversationID)
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].unreadCount = 0
        }
    }

    func openReminderPanel() {
        guard selectedConversation != nil else {
            return
        }
        isReminderPresented = true
    }

    func closeReminderPanel() {
        isReminderPresented = false
    }

    /// Cmd+R: schedule a local notification that brings the user back to the
    /// selected chat after the chosen delay.
    func scheduleReminder(after interval: TimeInterval, label: String) async {
        guard let conversation = selectedConversation else {
            return
        }
        isReminderPresented = false

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await dependencies.permissionManager.request(.notifications)
        } else if settings.authorizationStatus == .denied {
            showBanner(
                tone: .warning,
                title: "Notifications are off",
                message: "Allow notifications for i2Message in System Settings so reminders can fire.",
                actionTitle: "Open Settings"
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Reminder: \(conversation.title)"
        content.body = "You asked to come back to this conversation."
        content.sound = .default
        content.threadIdentifier = conversation.id.rawValue

        let request = UNNotificationRequest(
            identifier: "reminder.\(conversation.id.rawValue).\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(60, interval), repeats: false)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            showBanner(tone: .success, title: "Reminder set", message: "You'll be reminded about \(conversation.title) \(label).")
        } catch {
            showBanner(tone: .error, title: "Could not set reminder", message: error.localizedDescription)
        }
    }

    // MARK: - New message (Cmd+N)

    /// Cmd+N: open the in-app recipient picker instead of handing off to
    /// Messages.app, so a new conversation starts in the same window.
    func openNewMessage() {
        newMessageQuery = ""
        newMessageSuggestions = defaultRecipientSuggestions()
        isNewMessagePresented = true
        isCommandPalettePresented = false
        isSearchOverlayPresented = false
        focusRequest = .newMessageRecipient
    }

    func closeNewMessage() {
        isNewMessagePresented = false
        newMessageQuery = ""
        newMessageSuggestions = []
    }

    /// Esc anywhere: dismiss whatever is on top, one layer at a time.
    /// Returns false when nothing was open (so the key can pass through).
    @discardableResult
    func dismissTopmostOverlay() -> Bool {
        if isOnboardingPresented {
            isOnboardingPresented = false
            // Same flag ContentView's finish closure writes via @AppStorage.
            UserDefaults.standard.set(true, forKey: "hasSeenShortcutTour")
        } else if isCommandPalettePresented {
            closeCommandPalette()
        } else if isSearchOverlayPresented {
            isSearchOverlayPresented = false
        } else if isNewMessagePresented {
            closeNewMessage()
        } else if isInfoPanelPresented {
            isInfoPanelPresented = false
        } else if isReminderPresented {
            closeReminderPanel()
        } else if messageEditDraft != nil {
            cancelMessageEdit()
        } else if isSettingsPresented {
            isSettingsPresented = false
        } else if isThreadPanelPresented {
            closeThread()
        } else {
            return false
        }
        return true
    }

    /// Live-searches the full address book (falling back to loaded contacts)
    /// for the recipient picker.
    func updateNewMessageQuery(_ text: String) async {
        newMessageQuery = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newMessageSuggestions = defaultRecipientSuggestions()
            return
        }

        if dependencies.isLiveData {
            if let page = try? await dependencies.contactProvider.contacts(matching: trimmed, page: PageRequest(limit: 12)) {
                let matches = page.items.filter { !$0.isCurrentUser }
                if !matches.isEmpty {
                    newMessageSuggestions = matches
                    return
                }
            }
        }

        newMessageSuggestions = contacts
            .filter { contact in
                contact.displayName.localizedCaseInsensitiveContains(trimmed)
                    || contact.handles.contains { $0.value.localizedCaseInsensitiveContains(trimmed) }
            }
            .prefix(12)
            .map { $0 }
    }

    /// Resolves Return against suggestions for the text that is on screen now,
    /// not the previous debounce result. This prevents a quickly typed raw
    /// address from accidentally selecting a stale default contact.
    func submitNewMessage(selectedSuggestionID: ContactID?) async {
        let submittedQuery = newMessageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedQuery.isEmpty else { return }

        await updateNewMessageQuery(submittedQuery)
        guard newMessageQuery.trimmingCharacters(in: .whitespacesAndNewlines) == submittedQuery else {
            return
        }

        let selected = selectedSuggestionID.flatMap { id in
            newMessageSuggestions.first { $0.id == id }
        }
        if let contact = selected ?? newMessageSuggestions.first {
            await startConversation(with: contact)
        } else {
            await startConversation(withHandle: submittedQuery)
        }
    }

    private func defaultRecipientSuggestions() -> [Contact] {
        Array(filteredContacts.prefix(8))
    }

    /// Opens an existing thread with the contact if one is loaded, otherwise
    /// stages a pending conversation that sends to their handle on the first message.
    func startConversation(with contact: Contact) async {
        closeNewMessage()

        if let existing = conversations.first(where: { conversation in
            conversation.kind != .group && conversation.participants.contains { $0.id == contact.id }
        }) {
            await selectConversation(existing.id)
            focusRequest = .composer
            return
        }

        guard let handle = contact.handles.first else {
            showBanner(tone: .warning, title: "No address", message: "\(contact.displayName) has no phone number or email to message.")
            return
        }

        stagePendingConversation(title: contact.displayName, participants: [contact], handles: [handle])
    }

    /// Starts a pending conversation to a raw handle the user typed that does
    /// not match a known contact.
    func startConversation(withHandle raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        closeNewMessage()

        let isEmail = trimmed.contains("@")
        let kind: ContactHandleKind = isEmail ? .emailAddress : .phoneNumber
        let handle = ContactHandle(
            value: trimmed,
            normalizedValue: ContactHandleNormalizer.normalizedValue(trimmed, kind: kind),
            kind: kind,
            service: isEmail ? .iMessage : .unknown
        )
        stagePendingConversation(title: trimmed, participants: [], handles: [handle])
    }

    private func stagePendingConversation(title: String, participants: [Contact], handles: [ContactHandle]) {
        let conversation = Conversation(
            id: Self.pendingConversationID,
            title: title,
            participants: participants,
            kind: .direct,
            service: handles.first?.service ?? .iMessage,
            updatedAt: Date()
        )
        pendingNewConversation = PendingNewConversation(conversation: conversation, handles: handles)
        transcriptPages[Self.pendingConversationID] = .empty
        draftTexts[Self.pendingConversationID] = ""
        draftAttachments[Self.pendingConversationID] = []
        sidebarDestination = .conversations
        selectedConversationID = Self.pendingConversationID
        focusRequest = .composer
    }

    static let pendingConversationID = ConversationID(rawValue: "pending.new.conversation")

    // MARK: - Chat info (Cmd+I)

    /// Cmd+I: reveal shared photos and links for the selected chat. Fetches a
    /// wide page of history so media outside the visible transcript is included.
    func openInfoPanel() async {
        guard let conversation = selectedConversation else {
            return
        }
        isInfoPanelPresented = true
        if infoPanelConversationID == conversation.id, infoPanelPhase == .loaded {
            return
        }
        infoPanelConversationID = conversation.id
        infoPanelPhase = .loading
        infoPanelMedia = []
        infoPanelLinks = []

        let messages = await gatherConversationMessages(conversation.id)
        let media = messages
            .flatMap { $0.attachments }
            .filter { $0.kind == .image || $0.kind == .video }
        let links = Self.extractLinks(from: messages)

        // Bail out if the user moved on while we were loading.
        guard isInfoPanelPresented, infoPanelConversationID == conversation.id else {
            return
        }
        infoPanelMedia = media.reversed()
        infoPanelLinks = links
        infoPanelPhase = (media.isEmpty && links.isEmpty) ? .empty : .loaded
    }

    func closeInfoPanel() {
        isInfoPanelPresented = false
    }

    /// Best-effort collection of a conversation's messages for the info panel:
    /// tries a wide live page, falls back to fixtures, then to what's loaded.
    private func gatherConversationMessages(_ id: ConversationID) async -> [Message] {
        if let pending = pendingNewConversation, pending.conversation.id == id {
            return []
        }
        if dependencies.isLiveData, !(transcriptPages[id]?.usesFixtureData ?? false) {
            if let page = try? await dependencies.messageRepository.messages(
                in: id,
                page: PageRequest(limit: 400, direction: .older),
                around: nil
            ), !page.items.isEmpty {
                return page.items.sorted { $0.sentAt < $1.sentAt }
            }
        }
        if let seeded = dependencies.seed.messagesByConversation[id], !seeded.isEmpty {
            return seeded
        }
        return transcriptPages[id]?.messages ?? []
    }

    private static func extractLinks(from messages: [Message]) -> [SharedLink] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        var seen = Set<String>()
        var links: [SharedLink] = []
        for message in messages.sorted(by: { $0.sentAt > $1.sentAt }) {
            let text = message.body.plainText
            guard !text.isEmpty else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let url = match?.url else { return }
                let key = url.absoluteString
                guard seen.insert(key).inserted else { return }
                links.append(SharedLink(url: url, sentAt: message.sentAt))
            }
        }
        return links
    }

    // MARK: - Calendar suggestions

    private var dateMentionCache: [MessageID: DetectedDateMention?] = [:]
    private var dateMentionAccessOrder: [MessageID] = []

    /// Returns a calendar-worthy date/time detected in the message, if any.
    /// Cached so repeated bubble renders don't re-run the detector.
    func dateMention(in message: Message) -> DetectedDateMention? {
        if let cached = dateMentionCache[message.id] {
            touchDateMentionCacheEntry(message.id)
            return cached
        }
        let mention = DateMentionDetector.firstMention(in: message.body.plainText)
        dateMentionCache[message.id] = mention
        touchDateMentionCacheEntry(message.id)
        trimDateMentionCacheIfNeeded()
        return mention
    }

    var canAddToCalendar: Bool {
        dependencies.calendarWriter != nil
    }

    /// Adds the message's detected date to the calendar (Google, if configured
    /// in macOS Calendar; otherwise the default calendar).
    func addToCalendar(from message: Message) async {
        guard let writer = dependencies.calendarWriter,
              let mention = dateMention(in: message) else {
            return
        }
        let title = calendarTitle(for: message)
        do {
            let result = try await writer.addEvent(
                title: title,
                notes: calendarNotes(for: message),
                start: mention.date,
                hasTime: mention.hasTime
            )
            let when = Self.formattedEventDate(mention.date, hasTime: mention.hasTime)
            if result.isGoogleAccount {
                showBanner(
                    tone: .success,
                    title: "Added to \(result.calendarName)",
                    message: "\"\(title)\" on \(when)."
                )
            } else {
                // Landed in a non-Google calendar because no Google account is
                // set up in macOS Calendar. Let the user know how to route it.
                showBanner(
                    tone: .info,
                    title: "Added to \(result.calendarName)",
                    message: "\"\(title)\" on \(when). To sync to Google Calendar, add your Google account in System Settings › Internet Accounts."
                )
            }
        } catch {
            showBanner(
                tone: .error,
                title: "Couldn't add event",
                message: userFacingMessage(for: error),
                actionTitle: "Open Settings"
            )
        }
    }

    private func calendarTitle(for message: Message) -> String {
        let text = message.body.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        if firstLine.isEmpty {
            return "Event from message"
        }
        return firstLine.count <= 60 ? firstLine : String(firstLine.prefix(57)) + "…"
    }

    private func calendarNotes(for message: Message) -> String {
        let who = senderName(for: message.senderID)
        let convo = selectedConversation?.title ?? conversationTitle(for: message.conversationID)
        return "From \(who) in \(convo) (via i2Message)\n\n\(message.body.plainText)"
    }

    private static func formattedEventDate(_ date: Date, hasTime: Bool) -> String {
        date.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted)
    }

    /// Most recent conversation activity involving this contact, including
    /// group chats they participate in.
    func lastContactedAt(for contact: Contact) -> Date? {
        conversations
            .filter { conversation in conversation.participants.contains { $0.id == contact.id } }
            .map(\.updatedAt)
            .max()
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
            closeThread()
            selectedConversationID = nil
            highlightedMessageID = nil
            return
        }
        let currentIndex = selectedConversationID.flatMap { id in
            visible.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), visible.count - 1)
        await selectConversation(visible[nextIndex].id)
    }

    /// Jumps straight to the Nth conversation in the sidebar (⌘1…⌘9, ⌘0 → 10th).
    /// No-op when the list is shorter than the requested slot.
    func selectConversation(atIndex index: Int) async {
        let visible = filteredConversations
        guard index >= 0, index < visible.count else { return }
        await selectConversation(visible[index].id)
    }

    /// Browser-style ⌃Tab / ⌃⇧Tab cycling: wraps around the ends instead of
    /// clamping the way the up/down arrows do.
    func cycleConversation(offset: Int) async {
        let visible = filteredConversations
        guard !visible.isEmpty else { return }
        let currentIndex = selectedConversationID.flatMap { id in
            visible.firstIndex { $0.id == id }
        } ?? 0
        let count = visible.count
        let nextIndex = ((currentIndex + offset) % count + count) % count
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
        let preserveTopMessageID = !reset && conversationID == selectedConversationID
            ? visibleTranscriptMessages(from: state.messages, highlightedMessageID: highlightedMessageID).first?.id
            : nil

        // A conversation already served from fixtures pages locally; the live
        // repository does not know fixture conversation IDs.
        if dependencies.isLiveData, state.usesFixtureData {
            loadFixtureTranscriptPage(for: conversationID, reset: reset, preserving: preserveTopMessageID)
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
            if Task.isCancelled { return }
            let orderedItems = page.items.sorted { $0.sentAt < $1.sentAt }
            touchTranscriptPage(conversationID)
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
            if conversationID == selectedConversationID {
                reconcileThreadBaselines()
                if let anchor {
                    requestTranscriptScrollToMessage(anchor, conversationID: conversationID, anchor: .center, reason: .searchResult)
                } else if reset {
                    requestTranscriptTailScroll(conversationID: conversationID, reason: .initialLoad, messages: nextState.messages)
                } else {
                    requestTranscriptPreserveScroll(
                        previousTopMessageID: preserveTopMessageID,
                        conversationID: conversationID,
                        messages: nextState.messages
                    )
                }
            }
        } catch is CancellationError {
            // Superseded by a newer selection; leave the transcript untouched.
            return
        } catch {
            if Task.isCancelled { return }
            AppDiagnostics.failure("load_transcript", category: String(describing: type(of: error)))
            if dependencies.seed.messagesByConversation[conversationID] != nil {
                loadFixtureTranscriptPage(for: conversationID, reset: true)
                return
            }
            var failedState = transcriptPages[conversationID] ?? .empty
            failedState.isLoadingOlder = false
            failedState.phase = .failed(userFacingMessage(for: error))
            failedState.errorMessage = userFacingMessage(for: error)
            transcriptPages[conversationID] = failedState
            showBanner(tone: .error, title: "Could not load transcript", message: userFacingMessage(for: error), actionTitle: "Open Settings")
        }
    }

    /// Serves a transcript page for a fixture conversation directly from the
    /// seed dataset so fixture threads stay browsable when the live Messages
    /// store is unreadable.
    private func loadFixtureTranscriptPage(
        for conversationID: ConversationID,
        reset: Bool,
        preserving previousTopMessageID: MessageID? = nil
    ) {
        let allMessages = dependencies.seed.messagesByConversation[conversationID, default: []]
        let limit = max(settings.pageSize, 20)
        var state = transcriptPages[conversationID] ?? .empty

        let end: Int
        if reset || !state.usesFixtureData {
            end = allMessages.count
            state.messages = []
        } else if let cursor = state.olderCursor, cursor.rawValue.hasPrefix("older:"),
                  let boundary = Int(cursor.rawValue.dropFirst("older:".count)) {
            end = min(max(boundary, 0), allMessages.count)
        } else {
            end = 0
        }

        let start = max(0, end - limit)
        let page = Array(allMessages[start..<end])
        let existingIDs = Set(state.messages.map(\.id))
        state.messages = page.filter { !existingIDs.contains($0.id) } + state.messages
        state.olderCursor = start > 0 ? PageCursor(rawValue: "older:\(start)") : nil
        state.hasMoreOlder = start > 0
        state.isLoadingOlder = false
        state.totalCount = allMessages.count
        state.phase = state.messages.isEmpty ? .empty : .loaded
        state.errorMessage = nil
        state.usesFixtureData = true
        transcriptPages[conversationID] = state
        if conversationID == selectedConversationID {
            reconcileThreadBaselines()
            if reset {
                requestTranscriptTailScroll(conversationID: conversationID, reason: .initialLoad, messages: state.messages)
            } else {
                requestTranscriptPreserveScroll(
                    previousTopMessageID: previousTopMessageID,
                    conversationID: conversationID,
                    messages: state.messages
                )
            }
        }
    }

    func updateDraftText(_ text: String) {
        guard let selectedConversationID else {
            return
        }
        draftTexts[selectedConversationID] = text
    }

    func insertEmojiInCurrentDraft(_ rawEmoji: String) {
        guard let selectedConversationID,
              let emoji = EmojiCatalog.normalizedEmoji(from: rawEmoji)
        else {
            return
        }
        draftTexts[selectedConversationID, default: ""].append(emoji)
        focusRequest = .composer
    }

    func insertEmojiInThreadDraft(_ rawEmoji: String) {
        guard threadRootID != nil,
              let emoji = EmojiCatalog.normalizedEmoji(from: rawEmoji)
        else {
            return
        }
        threadDraftText.append(emoji)
    }

    @discardableResult
    func addDraftAttachments(fileURLs: [URL]) -> Int {
        guard let selectedConversationID else { return 0 }

        let readableFiles = fileURLs.filter { url in
            url.isFileURL && FileManager.default.fileExists(atPath: url.path)
        }
        guard !readableFiles.isEmpty else { return 0 }

        var attachments = draftAttachments[selectedConversationID, default: []]
        let existingURLs = Set(attachments.map(\.fileURL.standardizedFileURL))
        let additions = readableFiles.compactMap { fileURL -> DraftAttachment? in
            let standardized = fileURL.standardizedFileURL
            guard !existingURLs.contains(standardized) else { return nil }
            let contentType = try? standardized.resourceValues(forKeys: [.contentTypeKey]).contentType
            return DraftAttachment(
                id: AttachmentID(rawValue: "draft.file.\(UUID().uuidString)"),
                fileURL: standardized,
                filename: standardized.lastPathComponent,
                uniformTypeIdentifier: contentType?.identifier
            )
        }
        guard !additions.isEmpty else { return 0 }

        attachments.append(contentsOf: additions)
        draftAttachments[selectedConversationID] = attachments
        focusRequest = .composer
        return additions.count
    }

    /// Reads image content from `pasteboard`, writes each image's bytes to a
    /// real temp file with a correct extension, and appends it as a
    /// `DraftAttachment` on the selected conversation's draft — mirroring
    /// `addDroppedAttachment`. Returns `true` when at least one image was
    /// consumed so the composer can swallow the paste and skip inserting text;
    /// returns `false` for text-only / non-image pasteboards so ⌘V falls
    /// through to a normal text paste.
    @discardableResult
    func pasteImageAttachments(from pasteboard: NSPasteboard = .general) -> Bool {
        guard let selectedConversationID else {
            return false
        }
        let images = Self.pastedImages(from: pasteboard)
        guard !images.isEmpty else {
            return false
        }

        var attachments = draftAttachments[selectedConversationID, default: []]
        var appended = false
        for image in images {
            guard let attachment = Self.writeTemporaryDraftAttachment(for: image) else {
                continue
            }
            attachments.append(attachment)
            appended = true
        }
        guard appended else {
            return false
        }
        draftAttachments[selectedConversationID] = attachments
        focusRequest = .composer
        return true
    }

    /// A decoded image extracted from a pasteboard, ready to persist to disk.
    private struct PastedImage {
        var data: Data
        var fileExtension: String
        var uniformTypeIdentifier: String
        var baseName: String
    }

    private static func pastedImages(from pasteboard: NSPasteboard) -> [PastedImage] {
        // 1) Image files referenced by URL (e.g. copied from Finder). Filter to
        //    URLs whose contents are actually images so we never treat an
        //    arbitrary dragged file as an image.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]
        ) as? [URL], !urls.isEmpty {
            let fileImages: [PastedImage] = urls.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
                let uti = UTType(filenameExtension: ext)?.identifier ?? UTType.image.identifier
                let base = url.deletingPathExtension().lastPathComponent
                return PastedImage(
                    data: data,
                    fileExtension: ext,
                    uniformTypeIdentifier: uti,
                    baseName: base.isEmpty ? "Pasted Image" : base
                )
            }
            if !fileImages.isEmpty {
                return fileImages
            }
        }

        // 2) Raw image bytes placed directly on the pasteboard (screenshots,
        //    Preview, browsers). Preserve PNG/JPEG bytes as-is; normalize TIFF
        //    and any other NSImage-backed content to PNG.
        if let png = pasteboard.data(forType: .png) {
            return [PastedImage(data: png, fileExtension: "png", uniformTypeIdentifier: UTType.png.identifier, baseName: "Pasted Image")]
        }
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        if let jpeg = pasteboard.data(forType: jpegType) {
            return [PastedImage(data: jpeg, fileExtension: "jpeg", uniformTypeIdentifier: UTType.jpeg.identifier, baseName: "Pasted Image")]
        }
        if let tiff = pasteboard.data(forType: .tiff), let png = pngData(fromTIFF: tiff) {
            return [PastedImage(data: png, fileExtension: "png", uniformTypeIdentifier: UTType.png.identifier, baseName: "Pasted Image")]
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let png = pngData(fromTIFF: tiff) {
            return [PastedImage(data: png, fileExtension: "png", uniformTypeIdentifier: UTType.png.identifier, baseName: "Pasted Image")]
        }
        return []
    }

    private static func pngData(fromTIFF tiff: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func writeTemporaryDraftAttachment(for image: PastedImage) -> DraftAttachment? {
        let token = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("i2message-paste-\(token).\(image.fileExtension)")
        do {
            try image.data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return DraftAttachment(
            id: AttachmentID(rawValue: "draft.paste.\(token)"),
            fileURL: url,
            filename: "\(image.baseName).\(image.fileExtension)",
            uniformTypeIdentifier: image.uniformTypeIdentifier
        )
    }

    func removeDraftAttachment(_ attachment: DraftAttachment) {
        guard let selectedConversationID else {
            return
        }
        draftAttachments[selectedConversationID, default: []].removeAll { $0.id == attachment.id }
    }

    func message(with id: MessageID, in conversationID: ConversationID) -> Message? {
        transcriptPages[conversationID]?.messages.first { $0.id == id }
            ?? dependencies.seed.messagesByConversation[conversationID]?.first { $0.id == id }
    }

    func repliedMessage(for message: Message) -> Message? {
        guard let replyID = message.replyToMessageID else {
            return nil
        }
        return self.message(with: replyID, in: message.conversationID)
    }

    func requestAttachmentDescription(for attachment: MessageAttachment, in message: Message) {
        guard attachment.kind == .image,
              attachmentDescriptions[attachment.id] == nil,
              attachmentDescriptionTasks[attachment.id] == nil,
              let describer = dependencies.imageDescriber
        else {
            return
        }
        let isFixtureContent = !dependencies.isLiveData
            || (transcriptPages[message.conversationID]?.usesFixtureData ?? false)
        attachmentDescriptionTasks[attachment.id] = Task { [weak self] in
            var description = await describer.describe(attachment)
            if description == nil, isFixtureContent {
                // Fixture attachments have no real file on disk; show the demo
                // description so sample mode still demonstrates the feature.
                description = await MockImageDescriber().describe(attachment)
            }
            guard let self else { return }
            self.attachmentDescriptionTasks[attachment.id] = nil
            guard !Task.isCancelled else { return }
            if let description {
                self.rememberAttachmentDescription(description, for: attachment.id)
            }
        }
    }

    /// The current user's active tapback on `message`, if any. Drives the
    /// selected state of the floating tapback pill.
    func currentUserReaction(on message: Message) -> MessageReaction? {
        message.reactions.first { $0.senderID == dependencies.seed.currentUser.id }
    }

    /// Begins editing an outgoing iMessage. Fixture transcripts are mutable so
    /// previews/tests can demonstrate the full interaction. Real chat.db rows
    /// remain read-only and finish through a pasteboard + Messages.app handoff.
    func beginEditingMessage(_ message: Message) {
        let editsLocally = !dependencies.isLiveData
            || (transcriptPages[message.conversationID]?.usesFixtureData ?? false)

        if let restriction = messageEditRestriction(for: message, editsLocally: editsLocally) {
            showBanner(tone: .warning, title: "Can't edit this message", message: restriction)
            return
        }

        messageEditDraft = MessageEditDraft(
            message: message,
            text: message.body.plainText,
            editsLocally: editsLocally
        )
    }

    func updateMessageEditText(_ text: String) {
        messageEditDraft?.text = text
    }

    func cancelMessageEdit() {
        guard !isCompletingMessageEdit else { return }
        messageEditDraft = nil
    }

    var canCompleteMessageEdit: Bool {
        guard let draft = messageEditDraft else { return false }
        return !isCompletingMessageEdit
            && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.text != draft.originalText
    }

    func completeMessageEdit() async {
        guard let draft = messageEditDraft, canCompleteMessageEdit else { return }
        if let restriction = messageEditRestriction(for: draft.message, editsLocally: draft.editsLocally) {
            showBanner(tone: .warning, title: "Can't edit this message", message: restriction)
            messageEditDraft = nil
            return
        }

        isCompletingMessageEdit = true
        defer { isCompletingMessageEdit = false }

        if draft.editsLocally {
            completeFixtureMessageEdit(draft)
            return
        }

        guard let actions = dependencies.messagingActions else {
            showBanner(
                tone: .error,
                title: "Messages handoff unavailable",
                message: "The edited text is still here. Try again after reopening i2Message."
            )
            return
        }

        let conversation = conversations.first { $0.id == draft.message.conversationID }
            ?? (selectedConversation?.id == draft.message.conversationID ? selectedConversation : nil)
        do {
            _ = try await actions.preparePasteHandoff(PasteHandoffRequest(text: draft.text))
            _ = try await actions.openConversation(
                ConversationHandoffRequest(
                    conversationID: draft.message.conversationID,
                    displayTitle: conversation?.title,
                    handles: conversation?.participants.flatMap(\.handles) ?? []
                )
            )
            messageEditDraft = nil
            showBanner(
                tone: .info,
                title: "Edited text copied",
                message: "In Messages, Control-click the message, choose Edit, paste, then press Return."
            )
        } catch {
            showBanner(tone: .error, title: "Could not open Messages", message: userFacingMessage(for: error))
        }
    }

    private func messageEditRestriction(for message: Message, editsLocally: Bool) -> String? {
        guard message.direction == .outgoing else {
            return "Only messages you sent can be edited."
        }
        guard !message.isDeleted else {
            return "An unsent message can no longer be edited."
        }
        guard !message.body.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "This message has no editable text."
        }
        guard supportsNativeMessageEditing(message) else {
            return "Apple doesn't support editing this direct SMS, MMS, or RCS message."
        }
        guard message.editHistory.count < 5 else {
            return "Apple limits a sent message to five edits."
        }
        if !editsLocally, Date().timeIntervalSince(message.sentAt) > 15 * 60 {
            return "Apple's 15-minute edit window has expired."
        }
        return nil
    }

    private func supportsNativeMessageEditing(_ message: Message) -> Bool {
        if message.service == .iMessage {
            return true
        }

        // Apple also permits updates in mixed-protocol group conversations
        // when at least one other participant uses iMessage.
        guard let conversation = conversations.first(where: { $0.id == message.conversationID }),
              conversation.kind == .group else {
            return false
        }
        return conversation.service == .iMessage
            || conversation.participants.contains { participant in
                !participant.isCurrentUser && participant.handles.contains { $0.service == .iMessage }
            }
    }

    private func completeFixtureMessageEdit(_ draft: MessageEditDraft) {
        var state = transcriptPages[draft.message.conversationID] ?? .empty
        guard let index = state.messages.firstIndex(where: { $0.id == draft.message.id }) else {
            showBanner(tone: .error, title: "Message unavailable", message: "Reload the conversation and try again.")
            return
        }

        let originalText = state.messages[index].body.plainText
        state.messages[index].editHistory.append(MessageEditVersion(text: originalText, editedAt: Date()))
        state.messages[index].body = .text(draft.text)
        state.messages[index].isEdited = true
        transcriptPages[draft.message.conversationID] = state

        if let conversationIndex = conversations.firstIndex(where: { $0.id == draft.message.conversationID }),
           conversations[conversationIndex].lastMessage?.messageID == draft.message.id {
            conversations[conversationIndex].lastMessage?.text = draft.text
        }

        messageEditDraft = nil
        showBanner(tone: .success, title: "Message text updated", message: "The sample transcript now includes the edit history.")
    }

    func toggleReaction(_ kind: MessageReactionKind, on message: Message) {
        var state = transcriptPages[message.conversationID] ?? .empty
        guard let index = state.messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        guard !dependencies.isLiveData || state.usesFixtureData else {
            showBanner(
                tone: .info,
                title: "Tapbacks need Messages.app",
                message: "macOS does not let other apps send tapbacks. Use Open in Messages to react from Messages.app.",
                actionTitle: nil
            )
            return
        }

        let currentUserID = dependencies.seed.currentUser.id
        if let existing = state.messages[index].reactions.firstIndex(where: { $0.senderID == currentUserID && $0.kind == kind }) {
            state.messages[index].reactions.remove(at: existing)
        } else {
            state.messages[index].reactions.removeAll { $0.senderID == currentUserID }
            state.messages[index].reactions.append(
                MessageReaction(
                    id: "local.reaction.\(UUID().uuidString)",
                    kind: kind,
                    senderID: currentUserID,
                    createdAt: Date()
                )
            )
        }
        transcriptPages[message.conversationID] = state
    }

    func toggleCustomReaction(_ rawEmoji: String, on message: Message) {
        guard let emoji = EmojiCatalog.normalizedEmoji(from: rawEmoji) else {
            return
        }
        var state = transcriptPages[message.conversationID] ?? .empty
        guard let index = state.messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        guard !dependencies.isLiveData || state.usesFixtureData else {
            showBanner(
                tone: .info,
                title: "Reactions need Messages.app",
                message: "macOS does not let other apps send custom emoji reactions. Use Open in Messages to react from Messages.app.",
                actionTitle: nil
            )
            return
        }

        let currentUserID = dependencies.seed.currentUser.id
        if let existing = state.messages[index].reactions.firstIndex(where: {
            $0.senderID == currentUserID && $0.kind == .custom && $0.displayText == emoji
        }) {
            state.messages[index].reactions.remove(at: existing)
        } else {
            state.messages[index].reactions.removeAll { $0.senderID == currentUserID }
            state.messages[index].reactions.append(
                MessageReaction(
                    id: "local.reaction.\(UUID().uuidString)",
                    kind: .custom,
                    senderID: currentUserID,
                    createdAt: Date(),
                    displayText: emoji
                )
            )
        }
        transcriptPages[message.conversationID] = state
    }

    /// Resolves a conversation to a direct Messages Automation target. The
    /// modern Messages `chat` class accepts chat.db GUIDs, so any conversation
    /// with a GUID (1:1 or group) is addressed exactly; conversations without
    /// one fall back to a 1:1 buddy-handle send, then to handoff.
    private func directAutomationTarget(for conversationID: ConversationID) -> SendTarget? {
        let conversation = selectedConversation?.id == conversationID
            ? selectedConversation
            : conversations.first(where: { $0.id == conversationID })
        guard let conversation else { return nil }

        let others = conversation.participants.filter { !$0.isCurrentUser }

        // Prefer the chat GUID for iMessage threads: `chat id "<guid>"` addresses
        // the exact existing thread. Skip it for SMS/text threads — their chat
        // GUID carries an `any;-;` service prefix that Messages resolves to
        // iMessage, so the send fails (error 22) for recipients who are not on
        // iMessage. Those go through a service-qualified buddy send below, which
        // the command builder addresses on the SMS service.
        if conversation.service == .iMessage,
           let guid = conversation.chatGUID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !guid.isEmpty {
            return .existingChat(guid: guid)
        }
        if others.count == 1,
           let handle = others.first?.handles.first(where: {
               !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
           }) {
            return .handles([handle])
        }
        return nil
    }

    private func conversation(matching handles: [ContactHandle], in candidates: [Conversation]? = nil) -> Conversation? {
        let requested = Set(handles.map { ContactHandleNormalizer.normalizedValue($0.value, kind: $0.kind) })
        guard !requested.isEmpty else { return nil }
        return (candidates ?? conversations).first { conversation in
            guard conversation.kind != .group else { return false }
            let participantHandles = Set(
                conversation.participants
                    .filter { !$0.isCurrentUser }
                    .flatMap(\.handles)
                    .map { ContactHandleNormalizer.normalizedValue($0.value, kind: $0.kind) }
            )
            return !requested.isDisjoint(with: participantHandles)
        }
    }

    func sendCurrentDraft() async {
        guard !isSendingCurrentDraft, let selectedConversationID else {
            return
        }
        isSendingCurrentDraft = true
        defer { isSendingCurrentDraft = false }
        let isPending = pendingNewConversation?.conversation.id == selectedConversationID
        let pendingHandles = pendingNewConversation?.handles ?? []

        // Main composer sends are always normal conversation messages. Thread
        // replies are created only by the docked thread panel.
        let localTarget: SendTarget = isPending
            ? .handles(pendingNewConversation?.handles ?? [])
            : .existingConversation(selectedConversationID)
        let draft = MessageDraft(
            target: localTarget,
            text: currentDraftText,
            attachments: currentDraftAttachments,
            replyToMessageID: nil,
            requestedService: selectedConversation?.service
        )

        // Actual send resolves a real handle for one-to-one chats (so AppleScript
        // can deliver it) and still avoids any reply anchor.
        let sendTarget: SendTarget = isPending
            ? localTarget
            : (directAutomationTarget(for: selectedConversationID) ?? localTarget)
        let sendableDraft = MessageDraft(
            target: sendTarget,
            text: currentDraftText,
            attachments: currentDraftAttachments,
            replyToMessageID: nil,
            requestedService: selectedConversation?.service
        )

        do {
            if dependencies.isLiveData {
                await ensureAutomationPermission()
            }
            sendOperation = try await dependencies.messageSender.validate(sendableDraft)
            let receipt = try await dependencies.messageSender.send(sendableDraft)
            AppDiagnostics.operation("send_message", state: "accepted")
            let localEchoDraft = isPending
                ? MessageDraft(
                    target: .existingConversation(Self.pendingConversationID),
                    text: draft.text,
                    attachments: draft.attachments,
                    requestedService: draft.requestedService
                )
                : draft
            appendSentMessage(receipt: receipt, draft: localEchoDraft)
            draftTexts[selectedConversationID] = ""
            draftAttachments[selectedConversationID] = []
            sendOperation = nil
            try? await dependencies.searchIndexer.invalidateIndex(for: selectedConversationID)
            if isPending {
                await loadConversations()
                let resolvedID = receipt.conversationID ?? conversation(matching: pendingHandles)?.id
                if let resolvedID {
                    pendingNewConversation = nil
                    transcriptPages[Self.pendingConversationID] = nil
                    draftTexts[Self.pendingConversationID] = nil
                    draftAttachments[Self.pendingConversationID] = nil
                    await selectConversation(resolvedID)
                } else if dependencies.isLiveData {
                    showBanner(
                        tone: .success,
                        title: "Message sent",
                        message: "Waiting for the new conversation to appear in Messages."
                    )
                }
            } else if dependencies.isLiveData {
                scheduleTranscriptReload()
            }
            // Live sends confirm themselves: the message appears in the
            // transcript. A banner would just cover the conversation.
            if !dependencies.isLiveData {
                showBanner(
                    tone: .success,
                    title: "Message queued",
                    message: "Fixture send used the shared sending contract."
                )
            }
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
            searchContactMatches = []
            searchPhase = .idle
            searchTotalCount = nil
            searchHasMore = false
            searchPageCursor = nil
            return
        }

        if reset {
            await updateSearchContactMatches(query)
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

    func submitCurrentSearch() async {
        let submittedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedQuery.isEmpty else { return }
        await performSearch(reset: true)
        guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == submittedQuery else { return }
        if let first = exactSearchResults.first {
            await openSearchResult(first)
        } else if let snippet = semanticSnippets.first {
            await openSemanticSnippet(snippet)
        }
    }

    /// Contacts matching the current query, shown as their own section in the
    /// global (⌘⇧P) search overlay. Empty when the search is scoped to one chat.
    private func updateSearchContactMatches(_ query: String) async {
        guard searchConversationScope == nil else {
            searchContactMatches = []
            return
        }

        var pool = contacts
        if dependencies.isLiveData,
           let page = try? await dependencies.contactProvider.contacts(matching: query, page: PageRequest(limit: 20)) {
            let extra = page.items.filter { !$0.isCurrentUser }
            let existing = Set(pool.map(\.id))
            pool += extra.filter { !existing.contains($0.id) }
        }

        let matches = pool.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(query)
                || contact.handles.contains { $0.value.localizedCaseInsensitiveContains(query) }
        }
        .sorted { (lastContactedAt(for: $0) ?? .distantPast) > (lastContactedAt(for: $1) ?? .distantPast) }

        searchContactMatches = Array(matches.prefix(6))
    }

    /// Jumps to the contact's existing thread, or stages a new one, from search.
    func openSearchContact(_ contact: Contact) async {
        closeSearchOverlay()
        await startConversation(with: contact)
    }

    func openSearchResult(_ result: SearchResult) async {
        closeSearchOverlay()
        if let contactID = result.contactID, result.conversationID == nil {
            selectContact(contactID)
            return
        }

        if let conversationID = result.conversationID {
            await selectConversation(conversationID, highlightedMessageID: result.messageID)
        }
    }

    func openSemanticSnippet(_ snippet: SemanticSnippet) async {
        closeSearchOverlay()
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

    /// Rehydrates providers after grants made in System Settings. Permission
    /// badges alone are not enough: Contacts and Messages data that failed on
    /// first launch must be loaded again without requiring an app restart.
    func handleApplicationDidBecomeActive() async {
        let previous = permissionSnapshot
        await refreshPermissions()

        let fullDiskBecameAvailable = previous.status(for: .fullDiskAccess)?.state != .granted
            && permissionSnapshot.status(for: .fullDiskAccess)?.state == .granted
        let contactsBecameAvailable = previous.status(for: .contacts)?.state != .granted
            && permissionSnapshot.status(for: .contacts)?.state == .granted

        if fullDiskBecameAvailable || contactsBecameAvailable {
            await loadConversations()
            await loadContacts()
            if selectedConversationID == nil {
                selectedConversationID = conversations.first?.id
            }
            await loadSelectedConversation(reset: true)
            restartBackgroundIndexingAfterPermissionChange()
        }
    }

    func requestPermission(_ permission: AppPermission) async {
        do {
            let status = try await dependencies.permissionManager.request(permission)
            await refreshPermissions()
            if status.state == .granted {
                if permission == .contacts || permission == .fullDiskAccess {
                    await loadConversations()
                    await loadContacts()
                    if selectedConversationID == nil {
                        selectedConversationID = conversations.first?.id
                    }
                    await loadSelectedConversation(reset: true)
                    restartBackgroundIndexingAfterPermissionChange()
                }
                showBanner(tone: .success, title: "Permission updated", message: "\(permission.displayName) is available.")
            } else {
                showBanner(
                    tone: .warning,
                    title: "Permission still needed",
                    message: status.reason ?? "Allow \(permission.displayName) in System Settings, then return to i2Message.",
                    actionTitle: "Open Settings"
                )
            }
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
        cancelIndexingTask(message: "Restarting index rebuild")
        let task = startIndexingTask(
            exactEnabled: true,
            semanticEnabled: true,
            initialMessage: "Preparing local index",
            completionBanner: true
        )
        await task.value
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
        bannerDismissTask?.cancel()
        statusBanner = nil
    }

    func openSearchOverlay(scopedToCurrentConversation: Bool) {
        let nextScope = scopedToCurrentConversation ? selectedConversationID : nil
        if searchConversationScope != nextScope {
            searchConversationScope = nextScope
            exactSearchResults = []
            semanticSnippets = []
            searchContactMatches = []
            searchHasMore = false
            searchTotalCount = nil
            searchPageCursor = nil
            searchPhase = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .idle : .loading
            if searchPhase == .loading {
                Task { await performSearch(reset: true) }
            }
        }
        isSearchOverlayPresented = true
        isCommandPalettePresented = false
        focusRequest = .searchField
    }

    func closeSearchOverlay() {
        isSearchOverlayPresented = false
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
            openNewMessage()
        case .openSearch:
            openSearchOverlay(scopedToCurrentConversation: false)
        case .searchCurrentChat:
            openSearchOverlay(scopedToCurrentConversation: true)
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
            if !currentDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !currentDraftAttachments.isEmpty {
                _ = try await actions.preparePasteHandoff(
                    PasteHandoffRequest(text: currentDraftText, attachments: currentDraftAttachments)
                )
            }
            let result = try await actions.openConversation(
                ConversationHandoffRequest(
                    conversationID: conversation.id,
                    displayTitle: conversation.title,
                    handles: conversation.participants.flatMap(\.handles)
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
        if id == dependencies.seed.currentUser.id || id.rawValue == "current-user" {
            return "You"
        }
        return contact(for: id)?.displayName ?? "Unknown"
    }

    /// Direction-aware sender label. Outgoing messages carry no sender handle in
    /// chat.db, so resolve those to "You" instead of falling through to "System".
    func senderName(for message: Message) -> String {
        if message.direction == .outgoing {
            return "You"
        }
        return senderName(for: message.senderID)
    }

    // MARK: - Threads

    /// Direct replies to `message` within the loaded transcript, oldest first.
    /// iMessage stores every reply against the thread originator, so a thread is
    /// simply a root message plus the messages that point back to it.
    func threadReplies(to messageID: MessageID) -> [Message] {
        selectedMessages
            .filter { $0.replyToMessageID == messageID }
            .sorted { $0.sentAt < $1.sentAt }
    }

    func threadReplyCount(for message: Message) -> Int {
        threadReplyCount(forRoot: message.id)
    }

    func threadReplyCount(forRoot rootID: MessageID) -> Int {
        selectedMessages.reduce(into: 0) { count, message in
            if message.replyToMessageID == rootID { count += 1 }
        }
    }

    /// A message anchors a thread when at least one other message replies to it.
    func isThreadRoot(_ message: Message) -> Bool {
        message.replyToMessageID == nil && threadReplyCount(for: message) > 0
    }

    /// Main-transcript messages with thread replies folded away — a reply is
    /// hidden when its root is also loaded, so new thread activity shows up as a
    /// quiet indicator on the root instead of a fresh bubble in the channel.
    var visibleTranscriptMessages: [Message] {
        visibleTranscriptMessages(from: selectedMessages, highlightedMessageID: highlightedMessageID)
    }

    private func visibleTranscriptMessages(from messages: [Message], highlightedMessageID: MessageID?) -> [Message] {
        let loadedIDs = Set(messages.map(\.id))
        return messages.filter { message in
            if message.id == highlightedMessageID {
                return true
            }
            guard let parent = message.replyToMessageID else { return true }
            return !loadedIDs.contains(parent)
        }
    }

    private func transcriptScrollTarget(
        for messageID: MessageID,
        in messages: [Message],
        highlightedMessageID: MessageID?
    ) -> MessageID? {
        let visibleMessages = visibleTranscriptMessages(from: messages, highlightedMessageID: highlightedMessageID)
        let visibleIDs = Set(visibleMessages.map(\.id))
        if visibleIDs.contains(messageID) {
            return messageID
        }
        if let message = messages.first(where: { $0.id == messageID }),
           let parent = message.replyToMessageID,
           visibleIDs.contains(parent) {
            return parent
        }
        return nil
    }

    private func requestTranscriptScrollToMessage(
        _ messageID: MessageID,
        conversationID: ConversationID,
        anchor: TranscriptScrollAnchor,
        reason: TranscriptScrollReason
    ) {
        guard let messages = transcriptPages[conversationID]?.messages,
              let target = transcriptScrollTarget(
                for: messageID,
                in: messages,
                highlightedMessageID: highlightedMessageID
              ) else {
            return
        }
        transcriptScrollSequence += 1
        transcriptScrollIntent = TranscriptScrollIntent(
            sequence: transcriptScrollSequence,
            conversationID: conversationID,
            messageID: target,
            anchor: anchor,
            reason: reason
        )
    }

    private func requestTranscriptTailScroll(
        conversationID: ConversationID,
        reason: TranscriptScrollReason,
        messages: [Message]
    ) {
        guard let lastVisibleID = visibleTranscriptMessages(
            from: messages,
            highlightedMessageID: highlightedMessageID
        ).last?.id else {
            return
        }
        transcriptScrollSequence += 1
        transcriptScrollIntent = TranscriptScrollIntent(
            sequence: transcriptScrollSequence,
            conversationID: conversationID,
            messageID: lastVisibleID,
            anchor: .bottom,
            reason: reason
        )
    }

    private func requestTranscriptPreserveScroll(
        previousTopMessageID: MessageID?,
        conversationID: ConversationID,
        messages: [Message]
    ) {
        guard let previousTopMessageID,
              let target = transcriptScrollTarget(
                for: previousTopMessageID,
                in: messages,
                highlightedMessageID: highlightedMessageID
              ) else {
            return
        }
        transcriptScrollSequence += 1
        transcriptScrollIntent = TranscriptScrollIntent(
            sequence: transcriptScrollSequence,
            conversationID: conversationID,
            messageID: target,
            anchor: .top,
            reason: .olderPage
        )
    }

    /// True when a thread has picked up replies since the user last opened it.
    func hasUnseenThreadReplies(_ message: Message) -> Bool {
        guard isThreadRoot(message) else { return false }
        let current = threadReplyCount(for: message)
        guard let seen = threadSeenReplyCount[message.id] else { return false }
        return current > seen
    }

    /// Baselines existing threads as "seen" on first sighting so only genuinely
    /// new replies (arriving on a later refresh) light up the indicator.
    private func reconcileThreadBaselines() {
        for message in selectedMessages where isThreadRoot(message) {
            if threadSeenReplyCount[message.id] == nil {
                threadSeenReplyCount[message.id] = threadReplyCount(for: message)
            }
        }
    }

    /// The full thread (root first, then replies oldest→newest) for the pane.
    var threadPanelMessages: [Message] {
        guard let threadRootID,
              let root = selectedMessages.first(where: { $0.id == threadRootID }) else {
            return []
        }
        return [root] + threadReplies(to: threadRootID)
    }

    var threadPanelRoot: Message? {
        guard let threadRootID else { return nil }
        return selectedMessages.first { $0.id == threadRootID }
    }

    func openThread(rootID: MessageID) {
        threadRootID = rootID
        isThreadPanelPresented = true
        threadDraftText = ""
        // Opening the thread clears its "new activity" state.
        threadSeenReplyCount[rootID] = threadReplyCount(forRoot: rootID)
    }

    /// Opens the thread a given message belongs to — its root if it's a reply,
    /// or itself if it already anchors a thread.
    func openThread(for message: Message) {
        let root = message.replyToMessageID ?? message.id
        openThread(rootID: root)
    }

    func closeThread() {
        isThreadPanelPresented = false
        threadRootID = nil
        threadDraftText = ""
    }

    var canSendThreadReply: Bool {
        !isSendingThreadReply
            && threadRootID != nil
            && !threadDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Sends a reply into the open thread (root as the reply target) and keeps
    /// the composer inside the pane so the conversation stays threaded.
    func sendThreadReply() async {
        guard !isSendingThreadReply,
              let selectedConversationID,
              let rootID = threadRootID,
              canSendThreadReply else {
            return
        }
        isSendingThreadReply = true
        defer { isSendingThreadReply = false }

        let draft = MessageDraft(
            target: .existingConversation(selectedConversationID),
            text: threadDraftText,
            attachments: [],
            replyToMessageID: rootID,
            requestedService: selectedConversation?.service
        )

        // Messages AppleScript cannot create an anchored reply. Never send a
        // normal message and fabricate a threaded local echo; preserve the
        // draft and hand the user to Messages for the real reply action.
        if dependencies.isLiveData {
            if await handoffDraftForManualSend(draft: draft) {
                threadDraftText = ""
            } else {
                showBanner(
                    tone: .error,
                    title: "Could not open Messages",
                    message: "Thread replies must be completed in Messages.app."
                )
            }
            return
        }

        let sendableDraft = MessageDraft(
            target: directAutomationTarget(for: selectedConversationID) ?? .existingConversation(selectedConversationID),
            text: threadDraftText,
            attachments: [],
            replyToMessageID: nil,
            requestedService: selectedConversation?.service
        )

        do {
            if dependencies.isLiveData {
                await ensureAutomationPermission()
            }
            sendOperation = try await dependencies.messageSender.validate(sendableDraft)
            let receipt = try await dependencies.messageSender.send(sendableDraft)
            AppDiagnostics.operation("send_thread_reply", state: "accepted")
            appendSentMessage(receipt: receipt, draft: draft)
            threadDraftText = ""
            sendOperation = nil
            threadSeenReplyCount[rootID] = threadReplyCount(forRoot: rootID)
            try? await dependencies.searchIndexer.invalidateIndex(for: selectedConversationID)
            if dependencies.isLiveData {
                scheduleTranscriptReload()
            }
        } catch {
            AppDiagnostics.failure("send_thread_reply", category: String(describing: type(of: error)))
            sendOperation = nil
            showBanner(
                tone: .error,
                title: "Could not send reply",
                message: userFacingMessage(for: error)
            )
        }
    }

    func contact(for id: ContactID?) -> Contact? {
        guard let id else {
            return nil
        }
        // Conversation participants carry contacts resolved from raw Messages
        // handles (including non-address-book fallbacks), so search them too.
        return contacts.first { $0.id == id }
            ?? conversations.lazy.flatMap(\.participants).first { $0.id == id }
            ?? dependencies.seed.contacts.first { $0.id == id }
    }

    func requestContactThumbnail(for contact: Contact?) {
        guard let contact,
              contactThumbnails[contact.id] == nil,
              !contactThumbnailMisses.contains(contact.id),
              contactThumbnailTasks[contact.id] == nil,
              let photoProvider = dependencies.contactPhotoProvider
        else {
            return
        }
        contactThumbnailTasks[contact.id] = Task { [weak self] in
            do {
                let data = try await photoProvider.thumbnailData(for: contact.id)
                guard let self else { return }
                self.contactThumbnailTasks[contact.id] = nil
                guard !Task.isCancelled else { return }
                if let data {
                    self.rememberContactThumbnail(data, for: contact.id)
                } else {
                    self.rememberMissingContactThumbnail(for: contact.id)
                }
            } catch is CancellationError {
                self?.contactThumbnailTasks[contact.id] = nil
            } catch {
                self?.contactThumbnailTasks[contact.id] = nil
            }
        }
    }

    private func rememberAttachmentDescription(_ description: String, for id: AttachmentID) {
        attachmentDescriptions[id] = description
        touchAttachmentDescriptionCacheEntry(id)
        trimAttachmentDescriptionCacheIfNeeded()
    }

    private func touchAttachmentDescriptionCacheEntry(_ id: AttachmentID) {
        attachmentDescriptionAccessOrder.removeAll { $0 == id }
        attachmentDescriptionAccessOrder.append(id)
    }

    private func trimAttachmentDescriptionCacheIfNeeded() {
        while attachmentDescriptionAccessOrder.count > Self.maxAttachmentDescriptionCacheSize {
            let expiredID = attachmentDescriptionAccessOrder.removeFirst()
            attachmentDescriptions[expiredID] = nil
        }
    }

    private func rememberContactThumbnail(_ data: Data, for id: ContactID) {
        contactThumbnails[id] = data
        contactThumbnailMisses.remove(id)
        touchContactThumbnailCacheEntry(id)
        trimContactThumbnailCacheIfNeeded()
    }

    private func rememberMissingContactThumbnail(for id: ContactID) {
        contactThumbnailMisses.insert(id)
        touchContactThumbnailCacheEntry(id)
        trimContactThumbnailCacheIfNeeded()
    }

    private func touchContactThumbnailCacheEntry(_ id: ContactID) {
        contactThumbnailAccessOrder.removeAll { $0 == id }
        contactThumbnailAccessOrder.append(id)
    }

    private func trimContactThumbnailCacheIfNeeded() {
        while contactThumbnailAccessOrder.count > Self.maxContactThumbnailCacheSize {
            let expiredID = contactThumbnailAccessOrder.removeFirst()
            contactThumbnails[expiredID] = nil
            contactThumbnailMisses.remove(expiredID)
        }
    }

    private func touchDateMentionCacheEntry(_ id: MessageID) {
        dateMentionAccessOrder.removeAll { $0 == id }
        dateMentionAccessOrder.append(id)
    }

    private func trimDateMentionCacheIfNeeded() {
        while dateMentionAccessOrder.count > Self.maxDateMentionCacheSize {
            let expiredID = dateMentionAccessOrder.removeFirst()
            dateMentionCache[expiredID] = nil
        }
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
        let pageMessages = Array(messages[start..<messages.count])
        transcriptPages[first] = TranscriptPageState(
            messages: pageMessages,
            olderCursor: start > 0 ? PageCursor(rawValue: "older:\(start)") : nil,
            hasMoreOlder: start > 0,
            isLoadingOlder: false,
            phase: messages.isEmpty ? .empty : .loaded,
            totalCount: messages.count,
            errorMessage: nil,
            usesFixtureData: true
        )
        requestTranscriptTailScroll(conversationID: first, reason: .initialLoad, messages: pageMessages)
    }

    private func startObservingDataChanges() {
        observationTask?.cancel()
        let repository = dependencies.conversationRepository
        observationTask = Task { [weak self] in
            do {
                let isLive = self?.dependencies.isLiveData ?? false
                for try await nextConversations in repository.observeConversations(filter: ConversationFilter(includeArchived: false)) {
                    try Task.checkCancellation()
                    var sorted = nextConversations.sorted(by: MockAppDataset.conversationSort)
                    if isLive { sorted = Array(sorted.prefix(80)) }
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if let selectedConversationID = self.selectedConversationID,
                           !sorted.contains(where: { $0.id == selectedConversationID }),
                           let selected = self.conversations.first(where: { $0.id == selectedConversationID }) {
                            sorted.append(selected)
                        }
                        self.conversations = sorted
                        self.applyLocalUnreadOverrides()
                        self.applyLocalReadOverrides()
                        if let pending = self.pendingNewConversation,
                           let resolved = self.conversation(matching: pending.handles, in: sorted) {
                            self.pendingNewConversation = nil
                            self.transcriptPages[Self.pendingConversationID] = nil
                            self.draftTexts[Self.pendingConversationID] = nil
                            self.draftAttachments[Self.pendingConversationID] = nil
                            self.selectedConversationID = resolved.id
                        }
                    }
                    await self?.refreshSelectedTranscriptTail()
                    try Task.checkCancellation()
                    await MainActor.run { [weak self] in
                        self?.scheduleBackgroundIndexing()
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

    /// Coalesces reindex requests from the live-data observer. The Messages
    /// database changes constantly (read receipts, delivery, typing), so
    /// reindexing on every change token would keep the search index churning
    /// during active use. Waiting for a quiet gap keeps indexing off the hot
    /// path while chats are being switched.
    private func scheduleBackgroundIndexing() {
        backgroundIndexingDebounceTask?.cancel()
        backgroundIndexingDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.startBackgroundIndexingIfNeeded()
        }
    }

    private func startBackgroundIndexingIfNeeded() {
        guard settings.search.exactIndexEnabled || settings.search.semanticIndexEnabled else {
            cancelIndexingTask(message: "Indexing disabled")
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

        startIndexingTask(
            exactEnabled: settings.search.exactIndexEnabled,
            semanticEnabled: settings.search.semanticIndexEnabled,
            initialMessage: "Indexing in background",
            completionBanner: false
        )
    }

    /// Contacts and Full Disk Access can become available after startup. Any
    /// in-flight pass may have captured fallback handles or an unreadable
    /// corpus, so restart it immediately with the newly available providers.
    private func restartBackgroundIndexingAfterPermissionChange() {
        cancelIndexingTask(message: "Refreshing index metadata")
        startBackgroundIndexingIfNeeded()
    }

    private func cancelIndexingTask(message: String) {
        indexingTaskGeneration += 1
        indexingTask?.cancel()
        indexingTask = nil
        if indexingProgress.isIndexing {
            indexingProgress.isIndexing = false
            indexingProgress.message = message
        }
    }

    @discardableResult
    private func startIndexingTask(
        exactEnabled: Bool,
        semanticEnabled: Bool,
        initialMessage: String,
        completionBanner: Bool
    ) -> Task<Void, Never> {
        indexingTaskGeneration += 1
        let generation = indexingTaskGeneration
        let indexer = dependencies.searchIndexer
        let lastIndexedAt = indexingProgress.lastIndexedAt

        let task = Task { [weak self] in
            await MainActor.run { [weak self] in
                guard let self, self.indexingTaskGeneration == generation else { return }
                self.indexingProgress = IndexingProgress(
                    isIndexing: true,
                    exactProgress: exactEnabled ? 0 : 1,
                    semanticProgress: semanticEnabled ? 0 : 1,
                    lastIndexedAt: lastIndexedAt,
                    message: initialMessage
                )
            }

            do {
                if exactEnabled {
                    try Task.checkCancellation()
                    // A first full-history build takes minutes on a large
                    // library; surface the real fraction so the user can see
                    // it advancing instead of an idle spinner.
                    try await indexer.rebuildExactIndex { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            guard let self, self.indexingTaskGeneration == generation else { return }
                            self.indexingProgress.exactProgress = fraction
                            self.indexingProgress.message = fraction < 1
                                ? "Indexing messages (\(Int(fraction * 100))%)"
                                : initialMessage
                        }
                    }
                }

                if semanticEnabled {
                    try Task.checkCancellation()
                    await MainActor.run { [weak self] in
                        guard let self, self.indexingTaskGeneration == generation else { return }
                        self.indexingProgress.exactProgress = exactEnabled ? 1 : 0
                        self.indexingProgress.message = "Indexing semantic search"
                    }
                    try await indexer.rebuildSemanticIndex { [weak self] fraction in
                        Task { @MainActor [weak self] in
                            guard let self, self.indexingTaskGeneration == generation else { return }
                            self.indexingProgress.semanticProgress = fraction
                            if fraction < 1 {
                                self.indexingProgress.message = "Indexing semantic search (\(Int(fraction * 100))%)"
                            }
                        }
                    }
                }

                try Task.checkCancellation()
                await MainActor.run { [weak self] in
                    guard let self, self.indexingTaskGeneration == generation else { return }
                    self.indexingProgress = IndexingProgress(
                        isIndexing: false,
                        exactProgress: exactEnabled ? 1 : 0,
                        semanticProgress: semanticEnabled ? 1 : 0,
                        lastIndexedAt: Date(),
                        message: "Indexes are current"
                    )
                    self.indexingTask = nil
                    if completionBanner {
                        self.showBanner(tone: .success, title: "Indexes rebuilt", message: "Exact and semantic indexes finished locally.")
                    }
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self, self.indexingTaskGeneration == generation else { return }
                    self.indexingProgress.isIndexing = false
                    self.indexingProgress.message = "Indexing cancelled"
                    self.indexingTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.indexingTaskGeneration == generation else { return }
                    self.indexingProgress.isIndexing = false
                    self.indexingProgress.message = "Indexing paused"
                    self.indexingTask = nil
                    if completionBanner {
                        self.showBanner(tone: .error, title: "Indexing failed", message: self.userFacingMessage(for: error))
                    }
                }
            }
        }
        indexingTask = task
        return task
    }

    /// After a live send, fold the store's real row into the transcript once
    /// Messages has written it. Tail-merging (instead of a reset reload) keeps
    /// the scroll position and avoids a visible loading flash.
    private func scheduleTranscriptReload() {
        transcriptReloadTask?.cancel()
        transcriptReloadSequence += 1
        let sequence = transcriptReloadSequence
        transcriptReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshSelectedTranscriptTail()
            await MainActor.run { [weak self] in
                guard let self, self.transcriptReloadSequence == sequence else { return }
                self.transcriptReloadTask = nil
            }
        }
    }

    /// Merges the newest page of the selected conversation into the transcript
    /// tail when chat.db changes, without discarding already-loaded older pages —
    /// live arrivals (and tapback/edit/read-receipt changes on recent messages)
    /// appear without disturbing the reading position or pagination.
    func refreshSelectedTranscriptTail() async {
        guard dependencies.isLiveData, let conversationID = selectedConversationID else {
            return
        }
        guard refreshingTranscriptTailConversationIDs.insert(conversationID).inserted else {
            return
        }
        defer {
            refreshingTranscriptTailConversationIDs.remove(conversationID)
        }
        let state = transcriptPages[conversationID] ?? .empty
        guard state.phase == .loaded, !state.usesFixtureData else {
            return
        }

        do {
            let page = try await dependencies.messageRepository.messages(
                in: conversationID,
                page: PageRequest(limit: max(settings.pageSize, 20)),
                around: nil
            )
            let fresh = page.items.sorted { $0.sentAt < $1.sentAt }
            guard let oldestFresh = fresh.first else {
                return
            }
            guard conversationID == selectedConversationID else {
                return
            }
            var next = transcriptPages[conversationID] ?? .empty
            let freshIDs = Set(fresh.map(\.id))
            // Keep loaded history strictly older than the fresh window. Local
            // send echoes newer than the window are kept until the store's real
            // row appears (matched by direction + text), then dropped so they
            // don't duplicate.
            var retainedOlder: [Message] = []
            var retainedNewer: [Message] = []
            for message in next.messages {
                if freshIDs.contains(message.id) {
                    continue
                }
                if message.sentAt < oldestFresh.sentAt {
                    retainedOlder.append(message)
                } else if !fresh.contains(where: {
                    $0.direction == message.direction && $0.body.plainText == message.body.plainText
                }) {
                    retainedNewer.append(message)
                }
            }
            let merged = retainedOlder + fresh + retainedNewer
            guard merged != next.messages else {
                return
            }
            next.messages = merged
            next.phase = .loaded
            next.errorMessage = nil
            transcriptPages[conversationID] = next
            reconcileThreadBaselines()
        } catch {
            // Background refresh: keep the current transcript on failure.
            AppDiagnostics.failure("refresh_transcript_tail", category: String(describing: type(of: error)))
        }
    }

    /// Runs the Messages Automation preflight (showing the macOS consent
    /// prompt if needed) the first time the user sends in a session.
    private func ensureAutomationPermission() async {
        let state = permissionSnapshot.status(for: .appleEventsMessages)?.state
        guard state == nil || state == .notDetermined else {
            return
        }
        _ = try? await dependencies.permissionManager.request(.appleEventsMessages)
        await refreshPermissions()
    }

    private func handoffDraftForManualSend(draft: MessageDraft) async -> Bool {
        guard let actions = dependencies.messagingActions else { return false }

        let conversationID: ConversationID?
        let displayTitle: String?
        let handles: [ContactHandle]
        switch draft.target {
        case .existingConversation(let id):
            let conversation = conversations.first(where: { $0.id == id }) ?? selectedConversation
            conversationID = id
            displayTitle = conversation?.title
            handles = conversation?.participants.flatMap(\.handles) ?? []
        case .handles(let targetHandles):
            conversationID = nil
            displayTitle = pendingNewConversation?.conversation.title
            handles = targetHandles
        case .existingChat:
            conversationID = selectedConversation?.id
            displayTitle = selectedConversation?.title
            handles = selectedConversation?.participants.flatMap(\.handles) ?? []
        }

        do {
            _ = try await actions.preparePasteHandoff(
                PasteHandoffRequest(text: draft.text, attachments: draft.attachments)
            )
            _ = try await actions.openConversation(
                ConversationHandoffRequest(
                    conversationID: conversationID,
                    displayTitle: displayTitle,
                    handles: handles
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
        highlightedMessageID = nil
        if draft.replyToMessageID == nil {
            requestTranscriptScrollToMessage(
                message.id,
                conversationID: conversationID,
                anchor: .bottom,
                reason: .localSend
            )
        }
    }

    private func showBanner(
        tone: StatusBanner.Tone,
        title: String,
        message: String,
        actionTitle: String? = nil,
        autoDismissAfter: TimeInterval? = nil
    ) {
        bannerDismissTask?.cancel()
        let banner = StatusBanner(tone: tone, title: title, message: message, actionTitle: actionTitle)
        statusBanner = banner

        // Transient, non-actionable confirmations fade on their own; anything
        // the user might need to act on (warnings, errors, "Open Settings")
        // stays until dismissed.
        let delay = autoDismissAfter ?? Self.defaultBannerDismiss(tone: tone, actionTitle: actionTitle)
        guard let delay else { return }
        let bannerID = banner.id
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self, self.statusBanner?.id == bannerID else { return }
            self.statusBanner = nil
        }
    }

    private static func defaultBannerDismiss(tone: StatusBanner.Tone, actionTitle: String?) -> TimeInterval? {
        guard actionTitle == nil else { return nil }
        switch tone {
        case .success:
            return 3
        case .info:
            return 4
        case .warning, .error:
            return nil
        }
    }
}
