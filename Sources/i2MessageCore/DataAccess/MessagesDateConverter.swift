import Foundation

enum MessagesDateConverter {
    private static let cocoaReferenceDateOffset: TimeInterval = 978_307_200

    static func date(from rawValue: Int64?) -> Date? {
        guard let rawValue, rawValue > 0 else {
            return nil
        }

        let seconds: TimeInterval

        switch abs(rawValue) {
        case 1_000_000_000_000_000...:
            seconds = TimeInterval(rawValue) / 1_000_000_000 + cocoaReferenceDateOffset
        case 10_000_000_000...:
            seconds = TimeInterval(rawValue) / 1_000 + cocoaReferenceDateOffset
        case 100_000_000...:
            seconds = TimeInterval(rawValue) + cocoaReferenceDateOffset
        default:
            seconds = TimeInterval(rawValue)
        }

        return Date(timeIntervalSince1970: seconds)
    }

    static func stableDate(from rawValue: Int64?, fallbackRowID: Int64) -> Date {
        date(from: rawValue) ?? Date(timeIntervalSince1970: TimeInterval(fallbackRowID))
    }
}

struct MessagesPageCursor: Sendable, Equatable {
    enum Kind: String, Sendable {
        case conversation
        case message
        case attachment
    }

    var kind: Kind
    var sortValue: Int64
    var rowID: Int64

    func encode() -> PageCursor {
        PageCursor(rawValue: "\(kind.rawValue):v1:\(sortValue):\(rowID)")
    }

    static func decode(_ cursor: PageCursor?, expectedKind: Kind) -> MessagesPageCursor? {
        guard let rawValue = cursor?.rawValue else {
            return nil
        }

        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == expectedKind.rawValue,
              parts[1] == "v1",
              let sortValue = Int64(parts[2]),
              let rowID = Int64(parts[3])
        else {
            return nil
        }

        return MessagesPageCursor(kind: expectedKind, sortValue: sortValue, rowID: rowID)
    }
}

enum MessagesIdentifier {
    static func conversationID(rowID: Int64) -> ConversationID {
        ConversationID(rawValue: "chat:\(rowID)")
    }

    static func messageID(rowID: Int64) -> MessageID {
        MessageID(rawValue: "message:\(rowID)")
    }

    static func attachmentID(rowID: Int64) -> AttachmentID {
        AttachmentID(rawValue: "attachment:\(rowID)")
    }

    static func rowID(from conversationID: ConversationID) -> Int64? {
        rowID(from: conversationID.rawValue, prefix: "chat:")
    }

    static func rowID(from messageID: MessageID) -> Int64? {
        rowID(from: messageID.rawValue, prefix: "message:")
    }

    static func rowID(from attachmentID: AttachmentID) -> Int64? {
        rowID(from: attachmentID.rawValue, prefix: "attachment:")
    }

    private static func rowID(from rawValue: String, prefix: String) -> Int64? {
        guard rawValue.hasPrefix(prefix) else {
            return nil
        }

        return Int64(rawValue.dropFirst(prefix.count))
    }
}
