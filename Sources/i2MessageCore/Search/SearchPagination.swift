import Foundation

enum SearchCursor {
    private static let prefix = "search:v1:"

    static func offset(from request: PageRequest) -> Int {
        guard let rawValue = request.cursor?.rawValue,
              rawValue.hasPrefix(prefix),
              let offset = Int(rawValue.dropFirst(prefix.count)) else {
            return 0
        }

        switch request.direction {
        case .older:
            return max(0, offset)
        case .newer:
            return max(0, offset - request.limit)
        }
    }

    static func page<Element: Sendable>(
        items: [Element],
        requestedLimit: Int,
        offset: Int,
        totalCount: Int?
    ) -> Page<Element> {
        let limit = max(1, requestedLimit)
        let nextOffset = offset + items.count
        let hasMore = totalCount.map { nextOffset < $0 } ?? (items.count == limit)

        return Page(
            items: items,
            nextCursor: hasMore ? PageCursor(rawValue: "\(prefix)\(nextOffset)") : nil,
            previousCursor: offset > 0 ? PageCursor(rawValue: "\(prefix)\(max(0, offset - limit))") : nil,
            hasMore: hasMore,
            totalCount: totalCount
        )
    }
}
