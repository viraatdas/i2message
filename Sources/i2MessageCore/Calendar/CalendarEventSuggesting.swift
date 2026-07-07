import Foundation

/// A date/time reference detected inside a message, used to offer adding an
/// event to the user's calendar.
public struct DetectedDateMention: Hashable, Sendable {
    public var date: Date
    public var matchedText: String
    public var hasTime: Bool

    public init(date: Date, matchedText: String, hasTime: Bool) {
        self.date = date
        self.matchedText = matchedText
        self.hasTime = hasTime
    }
}

/// Finds calendar-worthy date/time references in message text using the same
/// local data detectors the system uses. Fully offline; no network.
public enum DateMentionDetector {
    public static func firstMention(in text: String, now: Date = Date()) -> DetectedDateMention? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        // Ignore matches that resolved to earlier than the start of today —
        // those are almost always references to the past, not plans to make.
        let earliest = Calendar.current.startOfDay(for: now)

        var found: DetectedDateMention?
        detector.enumerateMatches(in: text, options: [], range: range) { match, _, stop in
            guard let match, let date = match.date, date >= earliest else {
                return
            }
            let matched = nsText.substring(with: match.range)
            found = DetectedDateMention(
                date: date,
                matchedText: matched.trimmingCharacters(in: .whitespacesAndNewlines),
                hasTime: mentionHasTime(matched)
            )
            stop.pointee = true
        }
        return found
    }

    private static func mentionHasTime(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains(":") { return true }
        if lowered.contains("am") || lowered.contains("pm") { return true }
        if lowered.contains("noon") || lowered.contains("midnight") { return true }
        if lowered.contains("morning") || lowered.contains("afternoon")
            || lowered.contains("evening") || lowered.contains("tonight") { return true }
        return false
    }
}

public struct CalendarWriteResult: Sendable {
    /// Human-readable name of the calendar/account the event landed in.
    public var calendarName: String

    public init(calendarName: String) {
        self.calendarName = calendarName
    }
}

/// Writes an event to the user's calendar. The live implementation uses
/// EventKit, which surfaces any Google account configured in macOS Calendar,
/// so events can land directly in Google Calendar.
public protocol CalendarWriting: Sendable {
    func addEvent(
        title: String,
        notes: String?,
        start: Date,
        hasTime: Bool
    ) async throws -> CalendarWriteResult
}
