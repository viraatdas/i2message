@preconcurrency import AppKit
@preconcurrency import Contacts
import Foundation
@preconcurrency import UserNotifications

public final class MacOSPermissionManager: PermissionManaging, @unchecked Sendable {
    private let automation: (any MessagesAutomationControlling)?
    private let fileManager: FileManager
    private let dateProvider: @Sendable () -> Date

    public init(
        automation: (any MessagesAutomationControlling)? = nil,
        fileManager: FileManager = .default,
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.automation = automation
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    public func permissionSnapshot() async -> PermissionSnapshot {
        let fullDiskAccess = fullDiskAccessStatus()
        let contacts = contactsStatus()
        let appleEvents = await appleEventsStatus()
        let notifications = await notificationsStatus()
        let statuses = [fullDiskAccess, contacts, appleEvents, notifications]
        return PermissionSnapshot(statuses: statuses)
    }

    public func request(_ permission: AppPermission) async throws -> PermissionStatus {
        switch permission {
        case .fullDiskAccess:
            await openSystemSettings(for: .fullDiskAccess)
            return fullDiskAccessStatus()
        case .contacts:
            return try await requestContacts()
        case .appleEventsMessages:
            return try await requestAppleEvents()
        case .notifications:
            return try await requestNotifications()
        }
    }

    public func openSystemSettings(for permission: AppPermission) async {
        guard let url = settingsURL(for: permission) else {
            return
        }

        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    private func fullDiskAccessStatus() -> PermissionStatus {
        let messagesDatabasePath = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
            .path

        let fileExists = fileManager.fileExists(atPath: messagesDatabasePath)
        let isReadable = fileManager.isReadableFile(atPath: messagesDatabasePath)
        let state: PermissionState
        let reason: String

        if isReadable {
            state = .granted
            reason = "Messages database is readable for read-only indexing."
        } else if fileExists {
            state = .denied
            reason = "Messages database exists but is not readable. Grant Full Disk Access to i2Message."
        } else {
            state = .notDetermined
            reason = "Messages database was not found at the standard location."
        }

        return PermissionStatus(
            permission: .fullDiskAccess,
            state: state,
            reason: reason,
            lastCheckedAt: dateProvider()
        )
    }

    private func contactsStatus() -> PermissionStatus {
        let state = PermissionStateMapper.map(systemContactsState())
        return PermissionStatus(
            permission: .contacts,
            state: state,
            reason: reason(for: state, granted: "Contacts access is available for names, avatars, and handoff."),
            lastCheckedAt: dateProvider()
        )
    }

    private func requestContacts() async throws -> PermissionStatus {
        let store = CNContactStore()
        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }

        let state: PermissionState = granted ? .granted : .denied
        return PermissionStatus(
            permission: .contacts,
            state: state,
            reason: reason(for: state, granted: "Contacts access is available for names, avatars, and handoff."),
            lastCheckedAt: dateProvider()
        )
    }

    private func appleEventsStatus() async -> PermissionStatus {
        guard let automation else {
            return PermissionStatus(
                permission: .appleEventsMessages,
                state: .notDetermined,
                reason: "Messages Automation permission is checked when onboarding runs its preflight Apple Event.",
                lastCheckedAt: dateProvider()
            )
        }

        let messagesAvailable = await automation.isMessagesAvailable()
        return PermissionStatus(
            permission: .appleEventsMessages,
            state: messagesAvailable ? .notDetermined : .unsupported,
            reason: messagesAvailable
                ? "Messages Automation is available but has not been preflighted in this session."
                : "Messages.app could not be found.",
            lastCheckedAt: dateProvider()
        )
    }

    private func requestAppleEvents() async throws -> PermissionStatus {
        guard let automation else {
            await openSystemSettings(for: .appleEventsMessages)
            return PermissionStatus(
                permission: .appleEventsMessages,
                state: .notDetermined,
                reason: "Open Automation settings and allow i2Message to control Messages.",
                lastCheckedAt: dateProvider()
            )
        }

        do {
            _ = try await automation.execute(MessagesAppleScriptCommandBuilder.preflightCommand())
            return PermissionStatus(
                permission: .appleEventsMessages,
                state: .granted,
                reason: "Messages Automation preflight succeeded.",
                lastCheckedAt: dateProvider()
            )
        } catch let failure as MessagesAutomationFailure {
            let state: PermissionState = failure.kind == .appUnavailable ? .unsupported : .denied
            return PermissionStatus(
                permission: .appleEventsMessages,
                state: state,
                reason: failure.reason,
                lastCheckedAt: dateProvider()
            )
        } catch {
            return PermissionStatus(
                permission: .appleEventsMessages,
                state: .denied,
                reason: error.localizedDescription,
                lastCheckedAt: dateProvider()
            )
        }
    }

    private func notificationsStatus() async -> PermissionStatus {
        let settings = await notificationSettings()
        let state = PermissionStateMapper.map(systemNotificationState(settings.authorizationStatus))

        return PermissionStatus(
            permission: .notifications,
            state: state,
            reason: reason(for: state, granted: "Notifications are authorized."),
            lastCheckedAt: dateProvider()
        )
    }

    private func requestNotifications() async throws -> PermissionStatus {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        let state: PermissionState = granted ? .granted : .denied
        return PermissionStatus(
            permission: .notifications,
            state: state,
            reason: reason(for: state, granted: "Notifications are authorized."),
            lastCheckedAt: dateProvider()
        )
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func systemContactsState() -> SystemAuthorizationState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unsupported
        }
    }

    private func systemNotificationState(_ status: UNAuthorizationStatus) -> SystemAuthorizationState {
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unsupported
        }
    }

    private func reason(for state: PermissionState, granted: String) -> String {
        switch state {
        case .granted:
            return granted
        case .notDetermined:
            return "Permission has not been requested yet."
        case .denied:
            return "Permission was denied in System Settings."
        case .restricted:
            return "Permission is restricted by macOS policy."
        case .unsupported:
            return "Permission is unsupported on this Mac."
        }
    }

    private func settingsURL(for permission: AppPermission) -> URL? {
        let rawURL: String
        switch permission {
        case .fullDiskAccess:
            rawURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .contacts:
            rawURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        case .appleEventsMessages:
            rawURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .notifications:
            rawURL = "x-apple.systempreferences:com.apple.preference.notifications"
        }
        return URL(string: rawURL)
    }
}
