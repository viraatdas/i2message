import Foundation

/// Extracts plain message text from the `attributedBody` blob in chat.db.
///
/// Modern macOS Messages leaves `message.text` NULL and stores the body as an
/// NSArchiver "typedstream" of an NSAttributedString. Rather than reviving the
/// deprecated NSUnarchiver (which raises Objective-C exceptions on malformed
/// input), this walks the stream's known byte layout to pull out the first
/// NSString payload, which is the message text.
enum MessageBodyDecoder {
    static func plainText(fromAttributedBody data: Data?) -> String? {
        guard let data, !data.isEmpty else {
            return nil
        }

        guard let marker = "NSString".data(using: .utf8),
              let markerRange = data.range(of: marker)
        else {
            return nil
        }

        // Layout after the class name: 5 bytes of typedstream bookkeeping,
        // then a length-prefixed UTF-8 string. Lengths < 128 are a single
        // byte; larger strings use 0x81 + little-endian UInt16, and very
        // large ones 0x82 + little-endian UInt32.
        var index = markerRange.upperBound + 5
        guard index < data.count else {
            return nil
        }

        let length: Int
        switch data[index] {
        case 0x81:
            guard index + 2 < data.count else {
                return nil
            }
            length = Int(data[index + 1]) | (Int(data[index + 2]) << 8)
            index += 3
        case 0x82:
            guard index + 4 < data.count else {
                return nil
            }
            length = Int(data[index + 1])
                | (Int(data[index + 2]) << 8)
                | (Int(data[index + 3]) << 16)
                | (Int(data[index + 4]) << 24)
            index += 5
        default:
            length = Int(data[index])
            index += 1
        }

        guard length > 0, index + length <= data.count else {
            return nil
        }

        let textData = data.subdata(in: index..<(index + length))
        guard let text = String(data: textData, encoding: .utf8), !text.isEmpty else {
            return nil
        }

        // Strip the object-replacement characters Messages uses as attachment
        // placeholders inside the attributed body.
        let cleaned = text
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }

    /// Best text for a message row: prefer the plain `text` column, fall back
    /// to decoding `attributedBody`.
    static func bestText(text: String?, attributedBody: Data?) -> String? {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return plainText(fromAttributedBody: attributedBody)
    }

    /// Decodes the edit chain from `message_summary_info`: a binary plist whose
    /// "ec" key maps part index → array of versions, each `{d:` Cocoa reference
    /// timestamp`, t:` typedstream NSAttributedString`}`. Every recorded
    /// version is returned oldest-first, including the entry matching the
    /// current text (callers trim it).
    static func editHistory(fromSummaryInfo data: Data?) -> [MessageEditVersion] {
        guard let data, !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let info = plist as? [String: Any],
              let editedParts = info["ec"] as? [String: Any]
        else {
            return []
        }

        var versions: [MessageEditVersion] = []
        for key in editedParts.keys.sorted() {
            guard let entries = editedParts[key] as? [[String: Any]] else {
                continue
            }
            for entry in entries {
                guard let blob = entry["t"] as? Data,
                      let text = plainText(fromAttributedBody: blob)
                else {
                    continue
                }
                let timestamp = (entry["d"] as? Double) ?? 0
                versions.append(
                    MessageEditVersion(text: text, editedAt: Date(timeIntervalSinceReferenceDate: timestamp))
                )
            }
        }
        return versions.sorted { $0.editedAt < $1.editedAt }
    }
}
