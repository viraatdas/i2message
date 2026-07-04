import Foundation

public enum I2MessageError: Error, Equatable, Sendable {
    case permissionDenied(AppPermission, reason: String)
    case databaseUnavailable(path: String, reason: String)
    case readOnlyStoreRequired
    case unsupportedMutation(reason: String)
    case unsupportedCapability(reason: String)
    case appleEventsFailed(reason: String)
    case validationFailed(field: String, reason: String)
    case indexingFailed(reason: String)
    case notFound(resource: String, id: String)
    case cancelled
    case unknown(reason: String)
}

extension I2MessageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let permission, let reason):
            return "Permission denied for \(permission.rawValue): \(reason)"
        case .databaseUnavailable(let path, let reason):
            return "Messages database unavailable at \(path): \(reason)"
        case .readOnlyStoreRequired:
            return "Messages storage must be opened read-only."
        case .unsupportedMutation(let reason):
            return "Unsupported Messages mutation: \(reason)"
        case .unsupportedCapability(let reason):
            return "Unsupported capability: \(reason)"
        case .appleEventsFailed(let reason):
            return "Apple Events automation failed: \(reason)"
        case .validationFailed(let field, let reason):
            return "Invalid \(field): \(reason)"
        case .indexingFailed(let reason):
            return "Search indexing failed: \(reason)"
        case .notFound(let resource, let id):
            return "\(resource) not found: \(id)"
        case .cancelled:
            return "Operation cancelled."
        case .unknown(let reason):
            return "Unknown error: \(reason)"
        }
    }
}
