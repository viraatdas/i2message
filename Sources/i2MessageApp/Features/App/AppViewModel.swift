import Combine
import Foundation
import SwiftUI
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
    @Published private(set) var focusRequest: FocusRequest?
    @Published private(set) var statusBanner: StatusBanner?
    private var bannerDismissTask: Task<Void, Never>?
    @Published private(set) var isOffline = false

    @Published private var draftTexts: [ConversationID: String] = [:]
    @Published private var draftAttachments: [ConversationID: [DraftAttachment]] = [:]
    @Published private(set) var sendOperation: SendOperation?
    @Published private(set) var attachmentDescriptions: [AttachmentID: String] = [:]
    private var describingAttachmentIDs: Set<AttachmentID> = []
    @Published private(set) var contactThumbnails: [ContactID: Data] = [:]
    private var loadingThumbnailIDs: Set<ContactID> = []

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
            // Live mode intentionally loads only the most recent conversations
            // for now; older threads stay reachable through search.
            let page = try await dependencies.conversationRepository.conversations(
                page: PageRequest(limit: dependencies.isLiveData ? 10 : 200),
                filter: ConversationFilter(includeArchived: true)
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
        if let pending = pendingNewConversation, pending.conversation.id != id {
            pendingNewConversation = nil
        }
        if selectedConversationID != id {
            closeThread()
        }
        selectedConversationID = id
        markConversationRead(id)
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
        let handle = ContactHandle(
            value: trimmed,
            normalizedValue: trimmed.lowercased(),
            kind: isEmail ? .emailAddress : .phoneNumber,
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

    /// Returns a calendar-worthy date/time detected in the message, if any.
    /// Cached so repeated bubble renders don't re-run the detector.
    func dateMention(in message: Message) -> DetectedDateMention? {
        if let cached = dateMentionCache[message.id] {
            return cached
        }
        let mention = DateMentionDetector.firstMention(in: message.body.plainText)
        dateMentionCache[message.id] = mention
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
            selectedConversationID = nil
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

        // A conversation already served from fixtures pages locally; the live
        // repository does not know fixture conversation IDs.
        if dependencies.isLiveData, state.usesFixtureData {
            loadFixtureTranscriptPage(for: conversationID, reset: reset)
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
            if conversationID == selectedConversationID {
                reconcileThreadBaselines()
            }
        } catch {
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
    private func loadFixtureTranscriptPage(for conversationID: ConversationID, reset: Bool) {
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
              !describingAttachmentIDs.contains(attachment.id),
              let describer = dependencies.imageDescriber
        else {
            return
        }
        let isFixtureContent = !dependencies.isLiveData
            || (transcriptPages[message.conversationID]?.usesFixtureData ?? false)
        describingAttachmentIDs.insert(attachment.id)
        Task { [weak self] in
            var description = await describer.describe(attachment)
            if description == nil, isFixtureContent {
                // Fixture attachments have no real file on disk; show the demo
                // description so sample mode still demonstrates the feature.
                description = await MockImageDescriber().describe(attachment)
            }
            guard let self else { return }
            self.describingAttachmentIDs.remove(attachment.id)
            if let description {
                self.attachmentDescriptions[attachment.id] = description
            }
        }
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

        // Prefer the chat GUID: `chat id "<guid>"` addresses the exact existing
        // thread without re-resolving handles or risking a new conversation on
        // a different service.
        if let guid = conversation.chatGUID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !guid.isEmpty {
            return .existingChat(guid: guid)
        }
        // Fallback for conversations without a GUID: 1:1 buddy send.
        let others = conversation.participants.filter { !$0.isCurrentUser }
        if others.count == 1,
           let handle = others.first?.handles.first(where: {
               !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
           }) {
            return .handles([handle])
        }
        return nil
    }

    func sendCurrentDraft() async {
        guard let selectedConversationID else {
            return
        }
        let isPending = pendingNewConversation?.conversation.id == selectedConversationID

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
            if !isPending {
                appendSentMessage(receipt: receipt, draft: draft)
            }
            draftTexts[selectedConversationID] = ""
            draftAttachments[selectedConversationID] = []
            sendOperation = nil
            try? await dependencies.searchIndexer.invalidateIndex(for: selectedConversationID)
            if isPending {
                pendingNewConversation = nil
                transcriptPages[Self.pendingConversationID] = nil
                await loadConversations()
                if let realID = receipt.conversationID ?? conversations.first?.id {
                    await selectConversation(realID)
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
        bannerDismissTask?.cancel()
        statusBanner = nil
    }

    func openSearchOverlay(scopedToCurrentConversation: Bool) {
        searchConversationScope = scopedToCurrentConversation ? selectedConversationID : nil
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
        let loadedIDs = Set(selectedMessages.map(\.id))
        return selectedMessages.filter { message in
            guard let parent = message.replyToMessageID else { return true }
            return !loadedIDs.contains(parent)
        }
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
        threadRootID != nil
            && !threadDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Sends a reply into the open thread (root as the reply target) and keeps
    /// the composer inside the pane so the conversation stays threaded.
    func sendThreadReply() async {
        guard let selectedConversationID,
              let rootID = threadRootID,
              canSendThreadReply else {
            return
        }
        // Local echo carries the reply anchor so the pane threads it; the actual
        // send resolves a real handle (1:1) and drops the anchor.
        let draft = MessageDraft(
            target: .existingConversation(selectedConversationID),
            text: threadDraftText,
            attachments: [],
            replyToMessageID: rootID,
            requestedService: selectedConversation?.service
        )
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
              !loadingThumbnailIDs.contains(contact.id),
              let photoProvider = dependencies.contactPhotoProvider
        else {
            return
        }
        loadingThumbnailIDs.insert(contact.id)
        Task { [weak self] in
            let data = try? await photoProvider.thumbnailData(for: contact.id)
            guard let self else { return }
            self.loadingThumbnailIDs.remove(contact.id)
            if let data {
                self.contactThumbnails[contact.id] = data
            }
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
        transcriptPages[first] = TranscriptPageState(
            messages: Array(messages[start..<messages.count]),
            olderCursor: start > 0 ? PageCursor(rawValue: "older:\(start)") : nil,
            hasMoreOlder: start > 0,
            isLoadingOlder: false,
            phase: messages.isEmpty ? .empty : .loaded,
            totalCount: messages.count,
            errorMessage: nil,
            usesFixtureData: true
        )
    }

    private func startObservingDataChanges() {
        observationTask?.cancel()
        let repository = dependencies.conversationRepository
        let indexer = dependencies.searchIndexer
        observationTask = Task { [weak self] in
            do {
                let isLive = self?.dependencies.isLiveData ?? false
                for try await nextConversations in repository.observeConversations(filter: ConversationFilter(includeArchived: true)) {
                    try Task.checkCancellation()
                    var sorted = nextConversations.sorted(by: MockAppDataset.conversationSort)
                    if isLive {
                        sorted = Array(sorted.prefix(10))
                    }
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.conversations = sorted
                        self.applyLocalUnreadOverrides()
                        self.applyLocalReadOverrides()
                        if let selectedConversationID = self.selectedConversationID,
                           !sorted.contains(where: { $0.id == selectedConversationID }) {
                            self.selectedConversationID = sorted.first?.id
                            self.highlightedMessageID = nil
                        }
                    }
                    await self?.refreshSelectedTranscriptTail()
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

    /// After a live send, fold the store's real row into the transcript once
    /// Messages has written it. Tail-merging (instead of a reset reload) keeps
    /// the scroll position and avoids a visible loading flash.
    private func scheduleTranscriptReload() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self?.refreshSelectedTranscriptTail()
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
