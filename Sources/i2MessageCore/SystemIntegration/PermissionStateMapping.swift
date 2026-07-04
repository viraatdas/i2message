import Foundation

public enum SystemAuthorizationState: String, Codable, Hashable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case provisional
    case ephemeral
    case unsupported
}

public enum PermissionStateMapper {
    public static func map(_ state: SystemAuthorizationState) -> PermissionState {
        switch state {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .unsupported:
            return .unsupported
        }
    }
}
