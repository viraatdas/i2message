import Foundation

enum MessagesMapping {
    static func service(from rawValue: String?) -> MessageService {
        let normalized = (rawValue ?? "").lowercased()

        if normalized.contains("imessage") {
            return .iMessage
        }

        if normalized.contains("mms") {
            return .mms
        }

        if normalized.contains("rcs") {
            return .rcs
        }

        if normalized.contains("sms") || normalized.contains("text") {
            return .sms
        }

        return .unknown
    }

    static func conversationKind(style: Int?, participantCount: Int) -> ConversationKind {
        if participantCount > 1 || style == 43 {
            return .group
        }

        if participantCount == 1 {
            return .direct
        }

        return .unknown
    }

    static func direction(isFromMe: Bool?, itemType: Int?) -> MessageDirection {
        if itemType == 1 {
            return .system
        }

        return isFromMe == true ? .outgoing : .incoming
    }

    static func deliveryStatus(
        isFromMe: Bool?,
        isRead: Bool?,
        dateReadRaw: Int64?,
        dateDeliveredRaw: Int64?,
        errorCode: Int?
    ) -> MessageDeliveryStatus {
        if let errorCode, errorCode != 0 {
            return .failed
        }

        guard isFromMe == true else {
            return isRead == true ? .read : .delivered
        }

        if let dateReadRaw, dateReadRaw > 0 {
            return .read
        }

        if let dateDeliveredRaw, dateDeliveredRaw > 0 {
            return .delivered
        }

        return .sent
    }

    static func reactionKind(associatedMessageType: Int?, fallbackText: String?) -> MessageReactionKind? {
        guard let associatedMessageType else {
            return nil
        }

        switch associatedMessageType {
        case 2000:
            return .loved
        case 2001:
            return .liked
        case 2002:
            return .disliked
        case 2003:
            return .laughed
        case 2004:
            return .emphasized
        case 2005:
            return .questioned
        case 2006...2999:
            return .custom
        default:
            if fallbackText?.isEmpty == false {
                return .custom
            }
            return nil
        }
    }

    /// Balloon-plugin payloads (link previews and other app-message blobs)
    /// are bookkeeping data, not user files — they should not surface as
    /// attachments in transcripts.
    static func isPluginPayload(filename: String?, transferName: String?, uti: String?, mimeType: String?) -> Bool {
        [filename, transferName, uti, mimeType]
            .compactMap { $0?.lowercased() }
            .contains { value in
                value.hasSuffix(".pluginpayloadattachment")
                    || value.contains("pluginpayload")
                    || value.contains("messages.url.balloon")
            }
    }

    static func attachmentKind(filename: String, uti: String?, mimeType: String?, transferName: String?) -> AttachmentKind {
        let searchSpace = [uti, mimeType, transferName, filename]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if searchSpace.contains("sticker") {
            return .sticker
        }

        if searchSpace.contains("image") || searchSpace.contains(".heic") || searchSpace.contains(".jpg") || searchSpace.contains(".jpeg") || searchSpace.contains(".png") || searchSpace.contains(".gif") {
            return .image
        }

        if searchSpace.contains("video") || searchSpace.contains(".mov") || searchSpace.contains(".mp4") {
            return .video
        }

        if searchSpace.contains("audio") || searchSpace.contains(".m4a") || searchSpace.contains(".mp3") || searchSpace.contains(".caf") {
            return .audio
        }

        if filename.isEmpty {
            return .unknown
        }

        return .file
    }

    static func attachmentFilename(
        rawFilename: String?,
        transferName: String?,
        attachmentsDirectoryURL: URL?
    ) -> (displayName: String, fileURL: URL?, transferState: AttachmentTransferState) {
        let raw = rawFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = transferName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = [resolvedName, raw?.lastPathComponent].compactMap { value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }.first ?? "Attachment"

        guard let raw, !raw.isEmpty else {
            return (name, nil, .remotePlaceholder)
        }

        let expandedPath: String
        if raw.hasPrefix("~/") {
            expandedPath = NSString(string: raw).expandingTildeInPath
        } else if raw.hasPrefix("/") {
            expandedPath = raw
        } else if let attachmentsDirectoryURL {
            expandedPath = attachmentsDirectoryURL.appendingPathComponent(raw).path
        } else {
            expandedPath = raw
        }

        let url = URL(fileURLWithPath: expandedPath)
        let transferState: AttachmentTransferState = FileManager.default.fileExists(atPath: url.path) ? .local : .remotePlaceholder
        return (name, url, transferState)
    }
}

extension String {
    fileprivate var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
}
