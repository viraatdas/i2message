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

        let recipient = handles[0].normalizedValue.isEmpty ? handles[0].value : handles[0].normalizedValue
        guard !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MessagingActionError.recipientNotReachable(
                service: service,
                reason: "The selected contact handle is empty or could not be normalized."
            )
        }

        var lines = [
            "tell application \"Messages\"",
            "    set targetService to first service whose service type = iMessage",
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

    public static func automationHandles(for target: SendTarget) throws -> [ContactHandle] {
        switch target {
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
