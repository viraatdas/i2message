import Foundation

public enum AppPermission: String, Codable, Hashable, Sendable, CaseIterable {
    case fullDiskAccess
    case contacts
    case appleEventsMessages
    case notifications
}

public enum PermissionState: String, Codable, Hashable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unsupported
}

public struct PermissionStatus: Identifiable, Codable, Hashable, Sendable {
    public var id: AppPermission { permission }

    public var permission: AppPermission
    public var state: PermissionState
    public var reason: String?
    public var lastCheckedAt: Date

    public init(
        permission: AppPermission,
        state: PermissionState,
        reason: String? = nil,
        lastCheckedAt: Date
    ) {
        self.permission = permission
        self.state = state
        self.reason = reason
        self.lastCheckedAt = lastCheckedAt
    }
}

public struct PermissionSnapshot: Codable, Hashable, Sendable {
    public var statuses: [PermissionStatus]

    public init(statuses: [PermissionStatus]) {
        self.statuses = statuses
    }

    public func status(for permission: AppPermission) -> PermissionStatus? {
        statuses.first { $0.permission == permission }
    }
}
