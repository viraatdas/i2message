import Foundation

public enum PageDirection: String, Codable, Hashable, Sendable {
    case newer
    case older
}

public struct PageCursor: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

public struct PageRequest: Codable, Hashable, Sendable {
    public var cursor: PageCursor?
    public var limit: Int
    public var direction: PageDirection

    public init(cursor: PageCursor? = nil, limit: Int = 50, direction: PageDirection = .older) {
        self.cursor = cursor
        self.limit = limit
        self.direction = direction
    }
}

public struct Page<Element: Sendable>: Sendable {
    public var items: [Element]
    public var nextCursor: PageCursor?
    public var previousCursor: PageCursor?
    public var hasMore: Bool
    public var totalCount: Int?

    public init(
        items: [Element],
        nextCursor: PageCursor? = nil,
        previousCursor: PageCursor? = nil,
        hasMore: Bool,
        totalCount: Int? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.previousCursor = previousCursor
        self.hasMore = hasMore
        self.totalCount = totalCount
    }
}
