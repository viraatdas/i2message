import Foundation

public enum ContactHandleKind: String, Codable, Hashable, Sendable {
    case phoneNumber
    case emailAddress
    case unknown
}

public enum MessageService: String, Codable, Hashable, Sendable {
    case iMessage
    case sms
    case mms
    case rcs
    case unknown
}

public struct ContactHandle: Codable, Hashable, Sendable {
    public var value: String
    public var normalizedValue: String
    public var kind: ContactHandleKind
    public var service: MessageService

    public init(
        value: String,
        normalizedValue: String,
        kind: ContactHandleKind,
        service: MessageService
    ) {
        self.value = value
        self.normalizedValue = normalizedValue
        self.kind = kind
        self.service = service
    }
}

public struct ContactAvatar: Codable, Hashable, Sendable {
    public var initials: String
    public var colorSeed: String
    public var imageURL: URL?

    public init(initials: String, colorSeed: String, imageURL: URL? = nil) {
        self.initials = initials
        self.colorSeed = colorSeed
        self.imageURL = imageURL
    }
}

public struct Contact: Identifiable, Codable, Hashable, Sendable {
    public var id: ContactID
    public var displayName: String
    public var handles: [ContactHandle]
    public var avatar: ContactAvatar?
    public var isCurrentUser: Bool
    public var lastResolvedAt: Date?

    public init(
        id: ContactID,
        displayName: String,
        handles: [ContactHandle],
        avatar: ContactAvatar? = nil,
        isCurrentUser: Bool = false,
        lastResolvedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.handles = handles
        self.avatar = avatar
        self.isCurrentUser = isCurrentUser
        self.lastResolvedAt = lastResolvedAt
    }
}
