import Foundation
import i2MessageCore

extension AppDependencies {
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
            permissionManager: permissionManager
        )
        let corpusProvider = RepositorySearchIndexCorpusProvider(
            conversations: dataStack.conversations,
            messages: dataStack.messages,
            contacts: dataStack.contacts
        )
        let searchService = LocalSearchService(
            indexURL: defaultSearchIndexURL(fileManager: fileManager),
            corpusProvider: corpusProvider,
            semanticCandidateLimit: 50_000
        )

        return AppDependencies(
            isLiveData: true,
            seed: .rich,
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
            contactPhotoProvider: contacts
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

private struct RepositorySearchIndexCorpusProvider: SearchIndexCorpusProviding {
    let conversations: any ConversationRepository
    let messages: any MessageRepository
    let contacts: any ContactProviding
    // Index only recent conversations with bounded history for now so the
    // background indexer stays cheap on large Messages libraries.
    var conversationPageSize = 400
    var maxConversations = 10
    var messagePageSize = 500
    var maxMessagesPerConversation = 500

    func searchIndexCorpus() async throws -> SearchIndexCorpus {
        let conversationCorpus = try await loadConversations()
        async let contactCorpus = loadContacts()
        let messageCorpus = try await loadMessages(for: conversationCorpus)

        return SearchIndexCorpus(
            conversations: conversationCorpus,
            contacts: (try? await contactCorpus) ?? conversationCorpus.flatMap(\.participants),
            messages: messageCorpus
        )
    }

    private func loadConversations() async throws -> [Conversation] {
        var cursor: PageCursor?
        var allConversations: [Conversation] = []

        repeat {
            let page = try await conversations.conversations(
                page: PageRequest(cursor: cursor, limit: min(conversationPageSize, maxConversations)),
                filter: ConversationFilter(includeArchived: true)
            )
            allConversations.append(contentsOf: page.items)
            cursor = page.hasMore && allConversations.count < maxConversations ? page.nextCursor : nil
        } while cursor != nil

        return Array(allConversations.prefix(maxConversations))
    }

    private func loadContacts() async throws -> [Contact] {
        var cursor: PageCursor?
        var allContacts: [Contact] = []

        repeat {
            let page = try await contacts.contacts(
                matching: "",
                page: PageRequest(cursor: cursor, limit: 200)
            )
            allContacts.append(contentsOf: page.items)
            cursor = page.hasMore ? page.nextCursor : nil
        } while cursor != nil

        return allContacts
    }

    private func loadMessages(for conversations: [Conversation]) async throws -> [Message] {
        var allMessages: [Message] = []
        allMessages.reserveCapacity(conversations.count * min(messagePageSize, 120))

        for conversation in conversations {
            try Task.checkCancellation()
            var cursor: PageCursor?
            var loadedForConversation = 0

            repeat {
                let page = try await messages.messages(
                    in: conversation.id,
                    page: PageRequest(cursor: cursor, limit: messagePageSize, direction: .older),
                    around: nil
                )
                allMessages.append(contentsOf: page.items)
                loadedForConversation += page.items.count
                cursor = page.hasMore && loadedForConversation < maxMessagesPerConversation ? page.nextCursor : nil
            } while cursor != nil
        }

        return allMessages
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
