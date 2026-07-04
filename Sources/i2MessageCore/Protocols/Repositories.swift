import Foundation

public struct MessagesStoreDescriptor: Codable, Hashable, Sendable {
    public var databaseURL: URL
    public var attachmentsDirectoryURL: URL?
    public var openedAt: Date
    public var isReadOnly: Bool

    public init(
        databaseURL: URL,
        attachmentsDirectoryURL: URL? = nil,
        openedAt: Date,
        isReadOnly: Bool
    ) {
        self.databaseURL = databaseURL
        self.attachmentsDirectoryURL = attachmentsDirectoryURL
        self.openedAt = openedAt
        self.isReadOnly = isReadOnly
    }
}

public protocol MessagesDatabaseReading: Sendable {
    func openReadOnlyStore() async throws -> MessagesStoreDescriptor
}

public protocol ContactProviding: Sendable {
    func contacts(matching query: String, page: PageRequest) async throws -> Page<Contact>
    func contact(id: ContactID) async throws -> Contact
}

public protocol ConversationRepository: Sendable {
    func conversations(page: PageRequest, filter: ConversationFilter) async throws -> Page<Conversation>
    func conversation(id: ConversationID) async throws -> Conversation
    func observeConversations(filter: ConversationFilter) -> AsyncThrowingStream<[Conversation], Error>
}

public protocol MessageRepository: Sendable {
    func messages(
        in conversationID: ConversationID,
        page: PageRequest,
        around anchor: MessageID?
    ) async throws -> Page<Message>

    func message(id: MessageID) async throws -> Message
    func observeMessages(in conversationID: ConversationID) -> AsyncThrowingStream<[Message], Error>
}

public protocol AttachmentRepository: Sendable {
    func attachment(id: AttachmentID) async throws -> MessageAttachment
    func attachments(for messageID: MessageID) async throws -> [MessageAttachment]
}

public protocol SearchProviding: Sendable {
    func exactSearch(_ query: ExactSearchQuery, page: PageRequest) async throws -> Page<SearchResult>
    func semanticSearch(_ query: SemanticSearchQuery) async throws -> [SemanticSnippet]
}

public protocol SearchIndexing: Sendable {
    func rebuildExactIndex(progress: @Sendable @escaping (Double) -> Void) async throws
    func rebuildSemanticIndex(progress: @Sendable @escaping (Double) -> Void) async throws
    func invalidateIndex(for conversationID: ConversationID?) async throws
}

public protocol PermissionManaging: Sendable {
    func permissionSnapshot() async -> PermissionSnapshot
    func request(_ permission: AppPermission) async throws -> PermissionStatus
    func openSystemSettings(for permission: AppPermission) async
}

public protocol SettingsStoring: Sendable {
    func loadSettings() async throws -> AppSettings
    func saveSettings(_ settings: AppSettings) async throws
}

public protocol MessageSending: Sendable {
    /// Implementations must use supported automation and must never write directly to chat.db or related Messages storage.
    func validate(_ draft: MessageDraft) async throws -> SendOperation
    func send(_ draft: MessageDraft) async throws -> SendReceipt
}
