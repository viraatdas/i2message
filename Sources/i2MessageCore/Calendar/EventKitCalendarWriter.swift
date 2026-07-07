#if canImport(EventKit)
import EventKit
import Foundation

/// Adds events to the user's calendar via EventKit. When a Google account is
/// configured in macOS Calendar, its calendars appear here, so events written
/// to them sync straight to Google Calendar.
public final class EventKitCalendarWriter: CalendarWriting, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    public func addEvent(
        title: String,
        notes: String?,
        start: Date,
        hasTime: Bool
    ) async throws -> CalendarWriteResult {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            throw CalendarWriteError.accessDenied
        }

        guard let calendar = preferredCalendar() else {
            throw CalendarWriteError.noWritableCalendar
        }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.notes = notes
        event.startDate = start
        if hasTime {
            event.endDate = start.addingTimeInterval(60 * 60)
        } else {
            event.isAllDay = true
            event.endDate = start
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarWriteError.saveFailed(error.localizedDescription)
        }

        let name = calendar.source?.title ?? calendar.title
        return CalendarWriteResult(calendarName: name, isGoogleAccount: isGoogleCalendar(calendar))
    }

    /// Prefers a Google-backed calendar, then the default calendar, then any
    /// calendar that allows new events.
    private func preferredCalendar() -> EKCalendar? {
        let writable = store.calendars(for: .event).filter { $0.allowsContentModifications }
        if let google = writable.first(where: isGoogleCalendar) {
            return google
        }
        if let fallback = store.defaultCalendarForNewEvents, fallback.allowsContentModifications {
            return fallback
        }
        return writable.first
    }

    private func isGoogleCalendar(_ calendar: EKCalendar) -> Bool {
        guard let source = calendar.source else { return false }
        let title = source.title.lowercased()
        let isCalDAV = source.sourceType == .calDAV || source.sourceType == .subscribed
        return isCalDAV && (title.contains("google") || title.contains("gmail") || title.contains("@"))
    }
}

public enum CalendarWriteError: LocalizedError {
    case accessDenied
    case noWritableCalendar
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was declined. Allow it in System Settings › Privacy & Security › Calendars."
        case .noWritableCalendar:
            return "No writable calendar was found. Add an account in the Calendar app first."
        case .saveFailed(let reason):
            return "Could not save the event: \(reason)"
        }
    }
}
#endif
