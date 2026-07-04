import AppKit
import Contacts
import Foundation

public actor MacOSPermissionManager: PermissionManaging {
    private let messagesConfiguration: MessagesStoreConfiguration
    private let contactStore: CNContactStore
    private let now: @Sendable () -> Date

    public init(
        messagesConfiguration: MessagesStoreConfiguration = MessagesStoreConfiguration(),
        contactStore: CNContactStore = CNContactStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.messagesConfiguration = messagesConfiguration
        self.contactStore = contactStore
        self.now = now
    }

    public func permissionSnapshot() async -> PermissionSnapshot {
        PermissionSnapshot(
            statuses: AppPermission.allCases.map { status(for: $0) }
        )
    }

    public func request(_ permission: AppPermission) async throws -> PermissionStatus {
        switch permission {
        case .contacts:
            _ = try await requestContactsAccess()
            return status(for: .contacts)
        case .fullDiskAccess:
            await openSystemSettings(for: .fullDiskAccess)
            return status(for: .fullDiskAccess)
        case .appleEventsMessages, .notifications:
            return status(for: permission)
        }
    }

    public func openSystemSettings(for permission: AppPermission) async {
        let urlString: String

        switch permission {
        case .fullDiskAccess:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .contacts:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        case .appleEventsMessages:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .notifications:
            urlString = "x-apple.systempreferences:com.apple.preference.notifications"
        }

        guard let url = URL(string: urlString) else {
            return
        }

        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }

    private func status(for permission: AppPermission) -> PermissionStatus {
        switch permission {
        case .fullDiskAccess:
            return fullDiskAccessStatus()
        case .contacts:
            return contactsStatus()
        case .appleEventsMessages:
            return PermissionStatus(
                permission: permission,
                state: .notDetermined,
                reason: "Messages automation permission is checked when send or parity actions run.",
                lastCheckedAt: now()
            )
        case .notifications:
            return PermissionStatus(
                permission: permission,
                state: .notDetermined,
                reason: "Notification permission is managed by the app target.",
                lastCheckedAt: now()
            )
        }
    }

    private func fullDiskAccessStatus() -> PermissionStatus {
        let path = messagesConfiguration.databaseURL.path
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: path) else {
            return PermissionStatus(
                permission: .fullDiskAccess,
                state: .notDetermined,
                reason: "Messages database was not found at \(path).",
                lastCheckedAt: now()
            )
        }

        guard fileManager.isReadableFile(atPath: path) else {
            return PermissionStatus(
                permission: .fullDiskAccess,
                state: .denied,
                reason: "Messages database exists but is not readable. Full Disk Access is likely missing.",
                lastCheckedAt: now()
            )
        }

        do {
            let connection = try SQLiteConnection(readOnly: messagesConfiguration.databaseURL)
            _ = try MessagesDatabaseSchema.inspect(connection)
            return PermissionStatus(
                permission: .fullDiskAccess,
                state: .granted,
                reason: "Messages database can be opened read-only.",
                lastCheckedAt: now()
            )
        } catch {
            return PermissionStatus(
                permission: .fullDiskAccess,
                state: .denied,
                reason: error.localizedDescription,
                lastCheckedAt: now()
            )
        }
    }

    private func contactsStatus() -> PermissionStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return PermissionStatus(permission: .contacts, state: .granted, reason: nil, lastCheckedAt: now())
        case .notDetermined:
            return PermissionStatus(permission: .contacts, state: .notDetermined, reason: nil, lastCheckedAt: now())
        case .denied:
            return PermissionStatus(
                permission: .contacts,
                state: .denied,
                reason: "Contacts access is denied in System Settings.",
                lastCheckedAt: now()
            )
        case .restricted:
            return PermissionStatus(
                permission: .contacts,
                state: .restricted,
                reason: "Contacts access is restricted on this Mac.",
                lastCheckedAt: now()
            )
        @unknown default:
            return PermissionStatus(
                permission: .contacts,
                state: .unsupported,
                reason: "Contacts authorization returned an unknown status.",
                lastCheckedAt: now()
            )
        }
    }

    private func requestContactsAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: I2MessageError.permissionDenied(.contacts, reason: error.localizedDescription))
                    return
                }

                continuation.resume(returning: granted)
            }
        }
    }
}
