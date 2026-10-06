import EventKit
import Foundation

/// Read-only access to every calendar on the device (iCloud, and any Google or Outlook
/// account added in iOS Settings). Only title, start, end and the all-day flag are read.
final class CalendarService: CalendarDataSource {
    private var store = EKEventStore()

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted { store = EKEventStore() } // fresh store sees the newly granted calendars
        return granted
    }

    func events(from: Date, to: Date) -> [CalendarEvent] {
        guard hasAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate).compactMap { e in
            if e.status == .canceled { return nil }
            if let me = e.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined {
                return nil
            }
            return CalendarEvent(title: e.title ?? "", start: e.startDate, end: e.endDate, isAllDay: e.isAllDay)
        }
    }
}
