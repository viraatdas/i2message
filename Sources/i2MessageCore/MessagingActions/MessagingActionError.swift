import Foundation

public enum MessagingActionError: Error, Equatable, Sendable {
    case permissionRequired(AppPermission, reason: String)
    case appleEventsDisabled(reason: String)
    case messagesAppUnavailable(reason: String)
    case messagesAppNotSignedIn(reason: String)
    case recipientNotReachable(service: MessageService, reason: String)
    case attachmentTooLarge(filename: String, byteCount: Int64, maxByteCount: Int64)
    case serviceUnavailable(requested: MessageService, reason: String, fallback: String)
    case unsupportedCapability(kind: MessagingActionKind, reason: String, fallback: String)
    case validationFailed(field: String, reason: String)
    case automationFailed(reason: String)
    case handoffFailed(reason: String)
}

extension MessagingActionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionRequired(let permission, let reason):
            return "Permission required for \(permission.displayName): \(reason)"
        case .appleEventsDisabled(let reason):
            return "Messages Automation is disabled: \(reason)"
        case .messagesAppUnavailable(let reason):
            return "Messages.app is unavailable: \(reason)"
        case .messagesAppNotSignedIn(let reason):
            return "Messages.app is not ready to send: \(reason)"
        case .recipientNotReachable(let service, let reason):
            return "Recipient is not reachable on \(service.displayName): \(reason)"
        case .attachmentTooLarge(let filename, let byteCount, let maxByteCount):
            return "\(filename) is too large to send (\(Self.formattedByteCount(byteCount)); limit \(Self.formattedByteCount(maxByteCount)))."
        case .serviceUnavailable(let requested, let reason, _):
            return "\(requested.displayName) send is unavailable: \(reason)"
        case .unsupportedCapability(let kind, let reason, _):
            return "\(kind.displayName) is not supported: \(reason)"
        case .validationFailed(let field, let reason):
            return "Invalid \(field): \(reason)"
        case .automationFailed(let reason):
            return "Messages Automation failed: \(reason)"
        case .handoffFailed(let reason):
            return "Messages handoff failed: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .permissionRequired:
            return "Open i2Message permission settings and grant the requested macOS permission."
        case .appleEventsDisabled:
            return "Open System Settings, Privacy & Security, Automation, then allow i2Message to control Messages."
        case .messagesAppUnavailable:
            return "Install or restore Messages.app, then try again."
        case .messagesAppNotSignedIn:
            return "Open Messages.app and confirm that iMessage or Text Message Forwarding is signed in before retrying."
        case .recipientNotReachable:
            return "Open Messages.app to confirm the recipient can receive the selected service."
        case .attachmentTooLarge:
            return "Send a smaller attachment or share it through another app."
        case .serviceUnavailable(_, _, let fallback), .unsupportedCapability(_, _, let fallback):
            return fallback
        case .validationFailed:
            return "Fix the draft and try again."
        case .automationFailed:
            return "Open Messages.app and try the same send manually. If it succeeds, recheck Automation permission."
        case .handoffFailed:
            return "Open Messages.app manually and paste the prepared draft."
        }
    }

    private static func formattedByteCount(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
}

public extension AppPermission {
    var displayName: String {
        switch self {
        case .fullDiskAccess:
            return "Full Disk Access"
        case .contacts:
            return "Contacts"
        case .appleEventsMessages:
            return "Messages Automation"
        case .notifications:
            return "Notifications"
        }
    }
}

public extension MessageService {
    var displayName: String {
        switch self {
        case .iMessage:
            return "iMessage"
        case .sms:
            return "SMS"
        case .mms:
            return "MMS"
        case .rcs:
            return "RCS"
        case .unknown:
            return "Messages"
        }
    }
}

public extension MessagingActionKind {
    var displayName: String {
        switch self {
        case .sendMessage:
            return "Send Message"
        case .replyToMessage:
            return "Reply"
        case .startConversation:
            return "Start Conversation"
        case .sendAttachment:
            return "Send Attachment"
        case .openInMessages:
            return "Open in Messages"
        case .contactHandoff:
            return "Contact Handoff"
        case .notificationHook:
            return "Notifications"
        case .pasteHandoff:
            return "Paste Handoff"
        case .dragAndDropHandoff:
            return "Drag and Drop Handoff"
        case .markRead:
            return "Mark Read"
        }
    }
}
