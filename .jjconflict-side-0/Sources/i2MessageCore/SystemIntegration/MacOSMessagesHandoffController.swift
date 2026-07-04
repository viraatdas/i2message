@preconcurrency import AppKit
import Foundation

public final class MacOSMessagesHandoffController: MessagesHandoffControlling, @unchecked Sendable {
    private let automation: any MessagesAutomationControlling
    private let contactsBundleIdentifier: String

    public init(
        automation: any MessagesAutomationControlling,
        contactsBundleIdentifier: String = "com.apple.AddressBook"
    ) {
        self.automation = automation
        self.contactsBundleIdentifier = contactsBundleIdentifier
    }

    public func openMessages(with request: ConversationHandoffRequest) async throws {
        if !request.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !request.handles.isEmpty {
            let handoffText = handoffSummary(for: request)
            try await copyToPasteboard(PasteHandoffRequest(text: handoffText))
        }

        try await automation.openMessages()
    }

    public func openContact(with request: ContactHandoffRequest) async throws {
        let lines = [
            request.displayName,
            request.preferredHandle?.value,
            request.handles.map(\.value).joined(separator: ", ")
        ]
            .compactMap { $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !lines.isEmpty {
            try await copyToPasteboard(PasteHandoffRequest(text: lines.joined(separator: "\n")))
        }

        guard let url = await applicationURL(bundleIdentifier: contactsBundleIdentifier) else {
            try await automation.openMessages()
            return
        }

        let opened = await MainActor.run {
            NSWorkspace.shared.open(url)
        }

        if !opened {
            throw MessagingActionError.handoffFailed(reason: "macOS refused to open Contacts.app.")
        }
    }

    public func copyToPasteboard(_ request: PasteHandoffRequest) async throws {
        let succeeded = await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            var didWrite = false
            if !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                didWrite = pasteboard.setString(request.text, forType: .string) || didWrite
            }

            let fileObjects = request.attachments.map { $0.fileURL as NSURL }
            if !fileObjects.isEmpty {
                didWrite = pasteboard.writeObjects(fileObjects) || didWrite
            }

            return didWrite || request.text.isEmpty && request.attachments.isEmpty
        }

        if !succeeded {
            throw MessagingActionError.handoffFailed(reason: "macOS pasteboard refused the handoff payload.")
        }
    }

    public func dragItems(for request: DragHandoffRequest) async throws -> [MessagingHandoffItem] {
        var items: [MessagingHandoffItem] = []

        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            items.append(
                MessagingHandoffItem(
                    id: "drag.text",
                    kind: .text,
                    displayName: "Draft Text",
                    value: text
                )
            )
        }

        items += request.attachments.map { attachment in
            MessagingHandoffItem(
                id: "drag.file.\(attachment.id.rawValue)",
                kind: .fileURL,
                displayName: attachment.filename,
                value: attachment.fileURL.absoluteString
            )
        }

        return items
    }

    private func handoffSummary(for request: ConversationHandoffRequest) -> String {
        var parts: [String] = []
        if let displayTitle = request.displayTitle, !displayTitle.isEmpty {
            parts.append(displayTitle)
        }

        let handles = request.handles.map(\.value).filter { !$0.isEmpty }
        if !handles.isEmpty {
            parts.append(handles.joined(separator: ", "))
        }

        if !request.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(request.draftText)
        }

        return parts.joined(separator: "\n")
    }

    private func applicationURL(bundleIdentifier: String) async -> URL? {
        await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
    }
}
