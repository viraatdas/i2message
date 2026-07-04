import Foundation

public enum MessagingActionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case sendMessage
    case replyToMessage
    case startConversation
    case sendAttachment
    case openInMessages
    case contactHandoff
    case notificationHook
    case pasteHandoff
    case dragAndDropHandoff
    case markRead
}

public enum MessagingActionAvailabilityState: String, Codable, Hashable, Sendable {
    case available
    case requiresPermission
    case requiresUserHandoff
    case degraded
    case unsupported
    case unavailable
}

public struct MessagingFallback: Codable, Hashable, Sendable {
    public var title: String
    public var message: String
    public var actionLabel: String?

    public init(title: String, message: String, actionLabel: String? = nil) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
    }
}

public struct MessagingActionAvailability: Identifiable, Codable, Hashable, Sendable {
    public var id: MessagingActionKind { kind }

    public var kind: MessagingActionKind
    public var state: MessagingActionAvailabilityState
    public var requiredPermissions: [AppPermission]
    public var reason: String
    public var fallback: MessagingFallback?
    public var lastCheckedAt: Date

    public init(
        kind: MessagingActionKind,
        state: MessagingActionAvailabilityState,
        requiredPermissions: [AppPermission] = [],
        reason: String,
        fallback: MessagingFallback? = nil,
        lastCheckedAt: Date
    ) {
        self.kind = kind
        self.state = state
        self.requiredPermissions = requiredPermissions
        self.reason = reason
        self.fallback = fallback
        self.lastCheckedAt = lastCheckedAt
    }
}

public struct MessagingActionAvailabilitySnapshot: Codable, Hashable, Sendable {
    public var statuses: [MessagingActionAvailability]
    public var checkedAt: Date

    public init(statuses: [MessagingActionAvailability], checkedAt: Date) {
        self.statuses = statuses
        self.checkedAt = checkedAt
    }

    public func status(for kind: MessagingActionKind) -> MessagingActionAvailability? {
        statuses.first { $0.kind == kind }
    }
}

public enum MessagingActionOutcome: String, Codable, Hashable, Sendable {
    case completed
    case handedOff
    case unavailable
}

public struct MessagingActionResult: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: MessagingActionKind
    public var outcome: MessagingActionOutcome
    public var completedAt: Date
    public var userMessage: String
    public var fallback: MessagingFallback?

    public init(
        id: String,
        kind: MessagingActionKind,
        outcome: MessagingActionOutcome,
        completedAt: Date,
        userMessage: String,
        fallback: MessagingFallback? = nil
    ) {
        self.id = id
        self.kind = kind
        self.outcome = outcome
        self.completedAt = completedAt
        self.userMessage = userMessage
        self.fallback = fallback
    }
}

public struct ConversationHandoffRequest: Codable, Hashable, Sendable {
    public var conversationID: ConversationID?
    public var displayTitle: String?
    public var handles: [ContactHandle]
    public var draftText: String

    public init(
        conversationID: ConversationID? = nil,
        displayTitle: String? = nil,
        handles: [ContactHandle] = [],
        draftText: String = ""
    ) {
        self.conversationID = conversationID
        self.displayTitle = displayTitle
        self.handles = handles
        self.draftText = draftText
    }
}

public struct ContactHandoffRequest: Codable, Hashable, Sendable {
    public var contactID: ContactID?
    public var displayName: String
    public var handles: [ContactHandle]
    public var preferredHandle: ContactHandle?

    public init(
        contactID: ContactID? = nil,
        displayName: String,
        handles: [ContactHandle],
        preferredHandle: ContactHandle? = nil
    ) {
        self.contactID = contactID
        self.displayName = displayName
        self.handles = handles
        self.preferredHandle = preferredHandle
    }
}

public struct PasteHandoffRequest: Codable, Hashable, Sendable {
    public var text: String
    public var attachments: [DraftAttachment]

    public init(text: String = "", attachments: [DraftAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }
}

public struct DragHandoffRequest: Codable, Hashable, Sendable {
    public var text: String
    public var attachments: [DraftAttachment]

    public init(text: String = "", attachments: [DraftAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }
}

public enum MessagingHandoffItemKind: String, Codable, Hashable, Sendable {
    case text
    case fileURL
}

public struct MessagingHandoffItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: MessagingHandoffItemKind
    public var displayName: String
    public var value: String

    public init(id: String, kind: MessagingHandoffItemKind, displayName: String, value: String) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.value = value
    }
}

public struct MarkReadRequest: Codable, Hashable, Sendable {
    public var conversationID: ConversationID
    public var throughMessageID: MessageID?

    public init(conversationID: ConversationID, throughMessageID: MessageID? = nil) {
        self.conversationID = conversationID
        self.throughMessageID = throughMessageID
    }
}

public struct MessagingActionPolicy: Codable, Hashable, Sendable {
    public var maxAttachmentByteCount: Int64
    public var allowsDirectSMSAutomation: Bool
    public var allowsDirectGroupAutomation: Bool

    public init(
        maxAttachmentByteCount: Int64 = 100 * 1024 * 1024,
        allowsDirectSMSAutomation: Bool = false,
        allowsDirectGroupAutomation: Bool = false
    ) {
        self.maxAttachmentByteCount = maxAttachmentByteCount
        self.allowsDirectSMSAutomation = allowsDirectSMSAutomation
        self.allowsDirectGroupAutomation = allowsDirectGroupAutomation
    }
}

public extension MessagingActionAvailabilitySnapshot {
    static func conservativeDefault(checkedAt: Date) -> MessagingActionAvailabilitySnapshot {
        let openFallback = MessagingFallback(
            title: "Open Messages",
            message: "macOS does not expose this Messages.app feature safely. i2Message can hand off to Messages.app instead.",
            actionLabel: "Open Messages"
        )

        return MessagingActionAvailabilitySnapshot(
            statuses: [
                MessagingActionAvailability(
                    kind: .sendMessage,
                    state: .requiresPermission,
                    requiredPermissions: [.appleEventsMessages],
                    reason: "Direct sends require user-approved Messages Automation.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .replyToMessage,
                    state: .unsupported,
                    reason: "macOS does not expose a supported API for anchored inline replies.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .startConversation,
                    state: .requiresPermission,
                    requiredPermissions: [.appleEventsMessages],
                    reason: "Single-recipient iMessage starts can use Messages Automation after permission approval.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .sendAttachment,
                    state: .requiresPermission,
                    requiredPermissions: [.appleEventsMessages],
                    reason: "Attachment sends require Messages Automation and local readable files.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .openInMessages,
                    state: .requiresUserHandoff,
                    reason: "i2Message can open Messages.app, but macOS does not expose stable chat.db conversation IDs for deep linking.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .contactHandoff,
                    state: .requiresPermission,
                    requiredPermissions: [.contacts],
                    reason: "Contact handoff needs Contacts permission for reliable names and handles.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .notificationHook,
                    state: .requiresPermission,
                    requiredPermissions: [.notifications],
                    reason: "Notifications require macOS notification permission.",
                    fallback: nil,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .pasteHandoff,
                    state: .available,
                    reason: "Draft text and attachments can be placed on the pasteboard for explicit user handoff.",
                    fallback: nil,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .dragAndDropHandoff,
                    state: .available,
                    reason: "Local files and text can be represented as drag handoff payloads.",
                    fallback: nil,
                    lastCheckedAt: checkedAt
                ),
                MessagingActionAvailability(
                    kind: .markRead,
                    state: .unsupported,
                    reason: "Mark-read mutation is not safely exposed by macOS automation and direct chat.db writes are forbidden.",
                    fallback: openFallback,
                    lastCheckedAt: checkedAt
                )
            ],
            checkedAt: checkedAt
        )
    }
}
