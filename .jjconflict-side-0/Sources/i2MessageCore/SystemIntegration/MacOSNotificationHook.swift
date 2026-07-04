import Foundation
@preconcurrency import UserNotifications

public final class MacOSNotificationHook: MessagingNotificationHooking, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let dateProvider: @Sendable () -> Date

    public init(
        center: UNUserNotificationCenter = .current(),
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.center = center
        self.dateProvider = dateProvider
    }

    public func notificationPermissionStatus() async -> PermissionStatus {
        let settings = await notificationSettings()
        let state = PermissionStateMapper.map(systemNotificationState(settings.authorizationStatus))
        return PermissionStatus(
            permission: .notifications,
            state: state,
            reason: reason(for: state),
            lastCheckedAt: dateProvider()
        )
    }

    public func requestNotificationPermission() async throws -> PermissionStatus {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        let state: PermissionState = granted ? .granted : .denied
        return PermissionStatus(
            permission: .notifications,
            state: state,
            reason: reason(for: state),
            lastCheckedAt: dateProvider()
        )
    }

    public func post(_ payload: MessageNotificationPayload) async throws {
        let status = await notificationPermissionStatus()
        guard status.state == .granted else {
            throw MessagingActionError.permissionRequired(
                .notifications,
                reason: status.reason ?? "Notifications are not authorized."
            )
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.threadIdentifier = payload.threadIdentifier

        let request = UNNotificationRequest(
            identifier: "message.\(payload.conversationID.rawValue).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try await center.add(request)
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
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

    private func reason(for state: PermissionState) -> String {
        switch state {
        case .granted:
            return "Notifications are authorized."
        case .notDetermined:
            return "Notifications have not been requested yet."
        case .denied:
            return "Notifications were denied in System Settings."
        case .restricted:
            return "Notifications are restricted by macOS policy."
        case .unsupported:
            return "Notifications are unsupported on this Mac."
        }
    }
}
