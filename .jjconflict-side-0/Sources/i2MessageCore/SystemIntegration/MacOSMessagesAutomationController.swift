@preconcurrency import AppKit
import Foundation

public final class MacOSMessagesAutomationController: MessagesAutomationControlling, @unchecked Sendable {
    private let bundleIdentifiers: [String]

    public init(bundleIdentifiers: [String] = ["com.apple.MobileSMS", "com.apple.iChat"]) {
        self.bundleIdentifiers = bundleIdentifiers
    }

    public func isMessagesAvailable() async -> Bool {
        await messagesApplicationURL() != nil
    }

    public func execute(_ command: MessagesAppleScriptCommand) async throws -> MessagesAutomationResult {
        guard await isMessagesAvailable() else {
            throw MessagesAutomationFailure(
                kind: .appUnavailable,
                reason: "Messages.app could not be found by bundle identifier."
            )
        }

        return try await Task.detached(priority: .userInitiated) {
            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: command.source) else {
                throw MessagesAutomationFailure(
                    kind: .scriptFailed,
                    reason: "Could not compile \(command.redactedDescription)."
                )
            }

            let descriptor = script.executeAndReturnError(&errorInfo)
            if let errorInfo, errorInfo.count > 0 {
                throw Self.failure(from: errorInfo)
            }

            return MessagesAutomationResult(descriptor: descriptor.stringValue)
        }.value
    }

    public func openMessages() async throws {
        guard let url = await messagesApplicationURL() else {
            throw MessagesAutomationFailure(
                kind: .appUnavailable,
                reason: "Messages.app could not be found by bundle identifier."
            )
        }

        let opened = await MainActor.run {
            NSWorkspace.shared.open(url)
        }

        if !opened {
            throw MessagesAutomationFailure(
                kind: .appUnavailable,
                reason: "macOS refused to open Messages.app."
            )
        }
    }

    private func messagesApplicationURL() async -> URL? {
        await MainActor.run {
            for bundleIdentifier in bundleIdentifiers {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                    return url
                }
            }
            return nil
        }
    }

    private static func failure(from errorInfo: NSDictionary) -> MessagesAutomationFailure {
        let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        let message = (errorInfo[NSAppleScript.errorMessage] as? String)
            ?? (errorInfo[NSAppleScript.errorBriefMessage] as? String)
            ?? "Messages.app returned an AppleScript error."
        let lowercased = message.lowercased()

        if number == -1743
            || lowercased.contains("not authorized")
            || lowercased.contains("not allowed")
            || lowercased.contains("automation") {
            return MessagesAutomationFailure(kind: .appleEventsDenied, reason: message)
        }

        if lowercased.contains("sign in")
            || lowercased.contains("not signed in")
            || lowercased.contains("account") {
            return MessagesAutomationFailure(kind: .notSignedIn, reason: message)
        }

        if lowercased.contains("buddy")
            || lowercased.contains("recipient")
            || lowercased.contains("can't get")
            || lowercased.contains("cannot get") {
            return MessagesAutomationFailure(kind: .recipientNotReachable, reason: message)
        }

        if number == -600 || lowercased.contains("application") && lowercased.contains("not running") {
            return MessagesAutomationFailure(kind: .appUnavailable, reason: message)
        }

        return MessagesAutomationFailure(kind: .scriptFailed, reason: message)
    }
}
