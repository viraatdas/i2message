import Foundation

public struct MessagesDataAccessStack: Sendable {
    public let store: ReadOnlyMessagesStore
    public let contacts: ContactProviding
    public let conversations: ConversationRepository
    public let messages: MessageRepository
    public let attachments: AttachmentRepository
    public let permissions: PermissionManaging
    public let diagnostics: MessagesStoreDiagnosticService
    public let changeMonitor: MessagesChangeMonitoring

    public init(
        configuration: MessagesStoreConfiguration = MessagesStoreConfiguration(),
        contactProvider: (ContactProviding & ContactResolving)? = nil,
        permissionManager: PermissionManaging? = nil
    ) {
        let store = ReadOnlyMessagesStore(configuration: configuration)
        let contacts = contactProvider ?? SystemContactsProvider()
        let attachmentRepository = SQLiteAttachmentRepository(store: store)
        let changeMonitor = PollingMessagesChangeMonitor(store: store, pollInterval: configuration.pollInterval)

        self.store = store
        self.contacts = contacts
        self.attachments = attachmentRepository
        self.changeMonitor = changeMonitor
        self.diagnostics = MessagesStoreDiagnosticService(configuration: configuration)
        self.permissions = permissionManager ?? MacOSPermissionManager(messagesConfiguration: configuration)
        self.conversations = SQLiteConversationRepository(
            store: store,
            contactResolver: contacts,
            changeMonitor: changeMonitor
        )
        self.messages = SQLiteMessageRepository(
            store: store,
            contactResolver: contacts,
            attachmentRepository: attachmentRepository,
            changeMonitor: changeMonitor
        )
    }
}
