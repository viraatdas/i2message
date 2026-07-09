import Foundation

public enum MessagesAppleScriptCommandBuilder {
    public static func preflightCommand() -> MessagesAppleScriptCommand {
        MessagesAppleScriptCommand(
            source: """
            tell application "Messages"
                count services
            end tell
            """,
            redactedDescription: "Check Messages Automation permission"
        )
    }

    public static func sendCommand(
        for draft: MessageDraft,
        policy: MessagingActionPolicy = MessagingActionPolicy()
    ) throws -> MessagesAppleScriptCommand {
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !draft.attachments.isEmpty else {
            throw MessagingActionError.validationFailed(
                field: "message",
                reason: "Enter message text or attach at least one file."
            )
        }

        if draft.replyToMessageID != nil {
            throw MessagingActionError.unsupportedCapability(
                kind: .replyToMessage,
                reason: "Messages AppleScript can send to a buddy, but it cannot attach the send to a specific prior bubble.",
                fallback: "Open Messages.app and use its native reply UI."
            )
        }

        // Addressing an existing chat by GUID reaches group chats a single buddy
        // handle can't. The modern `chat` class accepts chat.db GUIDs directly
        // (the legacy `text chat` class does not).
        if case .existingChat(let guid) = draft.target {
            return try chatSendCommand(guid: guid, text: text, attachments: draft.attachments)
        }

        let handles = try automationHandles(for: draft.target)
        guard policy.allowsDirectGroupAutomation || handles.count == 1 else {
            throw MessagingActionError.unsupportedCapability(
                kind: .startConversation,
                reason: "Messages AppleScript does not expose a safe public way to create a true group chat from arbitrary handles.",
                fallback: "Open Messages.app with the draft on the pasteboard and complete the group conversation there."
            )
        }

        let service = draft.requestedService ?? handles.first?.service ?? .iMessage
        try validateService(service, policy: policy)

        let recipient = dialableRecipient(for: handles[0])
        guard !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MessagingActionError.recipientNotReachable(
                service: service,
                reason: "The selected contact handle is empty or could not be normalized."
            )
        }

        // Send on the conversation's real service. Hardcoding iMessage here made
        // green-bubble (SMS) threads go out as iMessage, which fails with error
        // 22 when the recipient is not registered on iMessage.
        let serviceTypeKeyword: String
        switch service {
        case .sms, .mms, .rcs:
            serviceTypeKeyword = "SMS"
        case .iMessage, .unknown:
            serviceTypeKeyword = "iMessage"
        }

        var lines = [
            "tell application \"Messages\"",
            "    set targetService to first service whose service type = \(serviceTypeKeyword)",
            "    set targetBuddy to buddy \(appleScriptString(recipient)) of targetService"
        ]

        if !text.isEmpty {
            lines.append("    send \(appleScriptString(text)) to targetBuddy")
        }

        for attachment in draft.attachments {
            lines.append("    send POSIX file \(appleScriptString(attachment.fileURL.path)) to targetBuddy")
        }

        lines.append("end tell")

        let attachmentSummary = draft.attachments.isEmpty ? "no attachments" : "\(draft.attachments.count) attachment(s)"
        return MessagesAppleScriptCommand(
            source: lines.joined(separator: "\n"),
            redactedDescription: "Send \(service.displayName) message to \(handles.count) recipient(s), \(attachmentSummary)"
        )
    }

    private static func chatSendCommand(
        guid: String,
        text: String,
        attachments: [DraftAttachment]
    ) throws -> MessagesAppleScriptCommand {
        let trimmedGUID = guid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGUID.isEmpty else {
            throw MessagingActionError.validationFailed(
                field: "chat",
                reason: "The conversation is missing a Messages chat identifier."
            )
        }

        var lines = [
            "tell application \"Messages\"",
            "    set targetChat to chat id \(appleScriptString(trimmedGUID))"
        ]

        if !text.isEmpty {
            lines.append("    send \(appleScriptString(text)) to targetChat")
        }

        for attachment in attachments {
            lines.append("    send POSIX file \(appleScriptString(attachment.fileURL.path)) to targetChat")
        }

        lines.append("end tell")

        let attachmentSummary = attachments.isEmpty ? "no attachments" : "\(attachments.count) attachment(s)"
        return MessagesAppleScriptCommand(
            source: lines.joined(separator: "\n"),
            redactedDescription: "Send message to existing chat, \(attachmentSummary)"
        )
    }

    public static func automationHandles(for target: SendTarget) throws -> [ContactHandle] {
        switch target {
        case .existingChat:
            throw MessagingActionError.unsupportedCapability(
                kind: .sendMessage,
                reason: "An existing-chat GUID target is addressed directly, not resolved to handles.",
                fallback: "Send to the chat GUID."
            )
        case .handles(let handles):
            let usableHandles = handles.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard !usableHandles.isEmpty else {
                throw MessagingActionError.validationFailed(
                    field: "recipient",
                    reason: "Choose at least one reachable Messages handle."
                )
            }
            return usableHandles
        case .existingConversation:
            throw MessagingActionError.unsupportedCapability(
                kind: .sendMessage,
                reason: "The app's read-only conversation identifier is not a public Messages Automation address.",
                fallback: "Resolve the conversation participants to handles, or open the conversation in Messages.app."
            )
        }
    }

    private static func validateService(
        _ service: MessageService,
        policy: MessagingActionPolicy
    ) throws {
        switch service {
        case .iMessage, .unknown:
            return
        case .sms, .mms, .rcs:
            guard policy.allowsDirectSMSAutomation else {
                throw MessagingActionError.serviceUnavailable(
                    requested: service,
                    reason: "macOS does not expose reliable direct \(service.displayName) sending through Messages Apple Events. Text Message Forwarding and carrier state must be confirmed inside Messages.app.",
                    fallback: "Open Messages.app with the draft on the pasteboard, then send from Apple's UI."
                )
            }
        }
    }

    /// The address Messages should send to. Uses the original handle string
    /// (not the normalized matching key, which strips the country code) and
    /// collapses phone numbers to a clean `+digits` form Messages can dial.
    private static func dialableRecipient(for handle: ContactHandle) -> String {
        let value = handle.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = value.isEmpty ? handle.normalizedValue : value

        switch handle.kind {
        case .emailAddress:
            return source
        case .phoneNumber, .unknown:
            if source.contains("@") { return source }
            let digits = source.filter(\.isNumber)
            guard !digits.isEmpty else { return source }
            return source.hasPrefix("+") ? "+" + digits : digits
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
