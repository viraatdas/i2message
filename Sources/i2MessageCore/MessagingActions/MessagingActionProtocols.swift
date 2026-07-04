import Foundation

public struct MessagesAppleScriptCommand: Equatable, Sendable {
    public var source: String
    public var redactedDescription: String

    public init(source: String, redactedDescription: String) {
        self.source = source
        self.redactedDescription = redactedDescription
    }
}

public struct MessagesAutomationResult: Equatable, Sendable {
    public var descriptor: String?

    public init(descriptor: String? = nil) {
        self.descriptor = descriptor
    }
}

public enum MessagesAutomationFailureKind: Equatable, Sendable {
    case appleEventsDenied
    case appUnavailable
    case notSignedIn
    case recipientNotReachable
    case scriptFailed
}

public struct MessagesAutomationFailure: Error, Equatable, Sendable {
    public var kind: MessagesAutomationFailureKind
    public var reason: String

    public init(kind: MessagesAutomationFailureKind, reason: String) {
        self.kind = kind
        self.reason = reason
    }
}

public protocol MessagesAutomationControlling: Sendable {
    func isMessagesAvailable() async -> Bool
    func execute(_ command: MessagesAppleScriptCommand) async throws -> MessagesAutomationResult
    func openMessages() async throws
}

public protocol MessagesHandoffControlling: Sendable {
    func openMessages(with request: ConversationHandoffRequest) async throws
    func openContact(with request: ContactHandoffRequest) async throws
    func copyToPasteboard(_ request: PasteHandoffRequest) async throws
    func dragItems(for request: DragHandoffRequest) async throws -> [MessagingHandoffItem]
}

public protocol DraftAttachmentInspecting: Sendable {
    func fileExists(at fileURL: URL) async -> Bool
    func byteCount(for fileURL: URL) async throws -> Int64?
}

public struct MessageNotificationPayload: Codable, Hashable, Sendable {
    public var conversationID: ConversationID
    public var title: String
    public var body: String
    public var threadIdentifier: String

    public init(
        conversationID: ConversationID,
        title: String,
        body: String,
        threadIdentifier: String
    ) {
        self.conversationID = conversationID
        self.title = title
        self.body = body
        self.threadIdentifier = threadIdentifier
    }
}

public protocol MessagingNotificationHooking: Sendable {
    func notificationPermissionStatus() async -> PermissionStatus
    func requestNotificationPermission() async throws -> PermissionStatus
    func post(_ payload: MessageNotificationPayload) async throws
}

public protocol MessagingActionServicing: MessageSending {
    func availabilitySnapshot() async -> MessagingActionAvailabilitySnapshot
    func startConversation(_ draft: MessageDraft) async throws -> SendReceipt
    func reply(_ draft: MessageDraft, to messageID: MessageID) async throws -> SendReceipt
    func openConversation(_ request: ConversationHandoffRequest) async throws -> MessagingActionResult
    func handoffContact(_ request: ContactHandoffRequest) async throws -> MessagingActionResult
    func preparePasteHandoff(_ request: PasteHandoffRequest) async throws -> MessagingActionResult
    func dragItems(for request: DragHandoffRequest) async throws -> [MessagingHandoffItem]
    func markRead(_ request: MarkReadRequest) async throws -> MessagingActionResult
}
