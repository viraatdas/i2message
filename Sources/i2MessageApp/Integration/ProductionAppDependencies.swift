import Foundation
import i2MessageCore

extension AppDependencies {
    /// How many of the most recent message documents get local semantic
    /// embeddings. Exact (FTS) search always covers the entire history;
    /// embedding hundreds of thousands of messages on device is prohibitive,
    /// so semantic search is bounded to the newest slice.
    static let semanticEmbeddingBudget = 50_000

    static func live(
        configuration: MessagesStoreConfiguration = MessagesStoreConfiguration(),
        fileManager: FileManager = .default
    ) -> AppDependencies {
        let automation = MacOSMessagesAutomationController()
        let systemPermissionManager = MacOSPermissionManager(automation: automation)
        let dataPermissionManager = MessagesDataAccessPermissionManager(messagesConfiguration: configuration)
        let permissionManager = CompositeAppPermissionManager(
            dataAccessPermissionManager: dataPermissionManager,
            systemPermissionManager: systemPermissionManager
        )
        let contacts = SystemContactsProvider()
        let dataStack = MessagesDataAccessStack(
            configuration: configuration,
            contactProvider: contacts,
            permissionManager: permissionManager
        )
        let handoff = MacOSMessagesHandoffController(automation: automation)
        let messagingActions = SafeMessagingActionService(
            automation: automation,
            handoff: handoff,
            permissionManager: permissionManager,
            // Allow SMS/text threads to send on the SMS service (via Text Message
            // Forwarding). Without this, green-bubble conversations either fail as
            // iMessage or bail to a manual handoff. If no SMS service is available
            // the AppleScript throws and the send still falls back to handoff.
            policy: MessagingActionPolicy(allowsDirectSMSAutomation: true)
        )
        let corpusProvider = RepositorySearchIndexCorpusProvider(
            conversations: dataStack.conversations,
            messages: dataStack.messages,
            contacts: dataStack.contacts
        )
        let searchService = LocalSearchService(
            indexURL: defaultSearchIndexURL(fileManager: fileManager),
            corpusProvider: corpusProvider,
            semanticCandidateLimit: semanticEmbeddingBudget
        )

        return AppDependencies(
            isLiveData: true,
            seed: .empty,
            conversationRepository: dataStack.conversations,
            messageRepository: dataStack.messages,
            contactProvider: dataStack.contacts,
            searchProvider: searchService,
            searchIndexer: searchService,
            permissionManager: permissionManager,
            messagingActions: messagingActions,
            settingsStore: UserDefaultsSettingsStore(),
            messageSender: messagingActions,
            imageDescriber: VisionImageDescriptionService(),
            contactPhotoProvider: contacts,
            calendarWriter: EventKitCalendarWriter()
        )
    }

    private static func defaultSearchIndexURL(fileManager: FileManager) -> URL {
        let baseDirectory = (
            try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        ) ?? fileManager.temporaryDirectory

        let directory = baseDirectory.appendingPathComponent("i2Message", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("SearchIndex.sqlite")
    }
}

private struct CompositeAppPermissionManager: PermissionManaging {
    let dataAccessPermissionManager: any PermissionManaging
    let systemPermissionManager: any PermissionManaging

    func permissionSnapshot() async -> PermissionSnapshot {
        async let dataSnapshot = dataAccessPermissionManager.permissionSnapshot()
        async let systemSnapshot = systemPermissionManager.permissionSnapshot()
        let data = await dataSnapshot
        let system = await systemSnapshot

        return PermissionSnapshot(
            statuses: AppPermission.allCases.compactMap { permission in
                switch permission {
                case .fullDiskAccess:
                    return data.status(for: permission) ?? system.status(for: permission)
                case .contacts, .appleEventsMessages, .notifications:
                    return system.status(for: permission) ?? data.status(for: permission)
                }
            }
        )
    }

    func request(_ permission: AppPermission) async throws -> PermissionStatus {
        switch permission {
        case .fullDiskAccess:
            return try await dataAccessPermissionManager.request(permission)
        case .contacts, .appleEventsMessages, .notifications:
            return try await systemPermissionManager.request(permission)
        }
    }

    func openSystemSettings(for permission: AppPermission) async {
        switch permission {
        case .fullDiskAccess:
            await dataAccessPermissionManager.openSystemSettings(for: permission)
        case .contacts, .appleEventsMessages, .notifications:
            await systemPermissionManager.openSystemSettings(for: permission)
        }
    }
}

/// Adapts the read-only Messages repositories into the streaming corpus
/// boundary. Exact search must cover the ENTIRE history, so there are no
/// conversation or per-conversation message caps here; memory stays bounded
/// because `LocalSearchService` consumes messages one paged batch at a time
/// instead of materializing the whole library.
private struct RepositorySearchIndexCorpusProvider: SearchIndexCorpusProviding {
    let conversations: any ConversationRepository
    let messages: any MessageRepository
    let contacts: any ContactProviding
    var conversationPageSize = 200
    var contactPageSize = 200

    func corpusSkeleton() async throws -> SearchIndexCorpusSkeleton {
        let conversationCorpus = try await loadConversations()
        let contactCorpus = (try? await loadContacts()) ?? conversationCorpus.flatMap(\.participants)
        return SearchIndexCorpusSkeleton(conversations: conversationCorpus, contacts: contactCorpus)
    }

    func messageBatches(in conversationID: ConversationID, batchSize: Int) -> AsyncThrowingStream<[Message], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var cursor: PageCursor?
                    repeat {
                        try Task.checkCancellation()
                        let page = try await messages.messages(
                            in: conversationID,
                            page: PageRequest(cursor: cursor, limit: batchSize, direction: .older),
                            around: nil
                        )
                        if !page.items.isEmpty {
                            continuation.yield(page.items)
                        }
                        cursor = page.hasMore ? page.nextCursor : nil
                    } while cursor != nil
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Full in-memory corpus. Only kept to satisfy the protocol's primitive —
    /// production indexing goes through `corpusSkeleton()`/`messageBatches`.
    func searchIndexCorpus() async throws -> SearchIndexCorpus {
        let skeleton = try await corpusSkeleton()
        var allMessages: [Message] = []

        for conversation in skeleton.conversations {
            for try await batch in messageBatches(in: conversation.id, batchSize: conversationPageSize) {
                allMessages.append(contentsOf: batch)
            }
        }

        return SearchIndexCorpus(
            conversations: skeleton.conversations,
            contacts: skeleton.contacts,
            messages: allMessages
        )
    }

    private func loadConversations() async throws -> [Conversation] {
        var cursor: PageCursor?
        var allConversations: [Conversation] = []

        repeat {
            try Task.checkCancellation()
            let page = try await conversations.conversations(
                page: PageRequest(cursor: cursor, limit: conversationPageSize),
                filter: ConversationFilter(includeArchived: true)
            )
            allConversations.append(contentsOf: page.items)
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil

        return allConversations
    }

    private func loadContacts() async throws -> [Contact] {
        var cursor: PageCursor?
        var allContacts: [Contact] = []

        repeat {
            let page = try await contacts.contacts(
                matching: "",
                page: PageRequest(cursor: cursor, limit: contactPageSize)
            )
            allContacts.append(contentsOf: page.items)
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil

        return allContacts
    }
}

private actor UserDefaultsSettingsStore: SettingsStoring {
    private let key: String
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String = "dev.viraat.i2message.settings", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func loadSettings() async throws -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return AppSettings(pageSize: 50)
        }
        return try decoder.decode(AppSettings.self, from: data)
    }

    func saveSettings(_ settings: AppSettings) async throws {
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: key)
    }
}
