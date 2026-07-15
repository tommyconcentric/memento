import Foundation
import SwiftData
import EventKit
import SwiftUI

/// Mirrors everyone's birthdays and important dates into a dedicated
/// "Memento" calendar in the user's Calendar app, so it can be shown or
/// hidden like any built-in calendar (Birthdays, Holidays, …). Independent
/// of NotificationManager's per-date reminder toggle — every date syncs
/// here regardless, matching the in-app Calendar tab.
enum CalendarSyncManager {
    static let enabledKey = "appleCalendarSyncEnabled"
    private static let calendarTitle = "Memento"
    private static let store = EKEventStore()

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func refreshFromContext(_ context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        refresh(people: people)
    }

    static func refresh(people: [Person]) {
        guard UserDefaults.standard.bool(forKey: enabledKey),
              let calendar = findOrCreateCalendar() else { return }

        removeAllEvents(in: calendar)

        for person in people where !person.isDeceased {
            if let birthday = person.birthday {
                addYearlyEvent(title: "🎂 \(person.name)'s Birthday", date: birthday, calendar: calendar)
            }
            for item in person.importantDatesArray {
                addYearlyEvent(title: "\(item.label) — \(person.name)", date: item.date, calendar: calendar)
            }
        }
        try? store.commit()
    }

    /// Deletes the "Memento" calendar and everything in it — call when the
    /// user turns the sync toggle off.
    static func removeCalendar() {
        guard let calendar = existingCalendar() else { return }
        try? store.removeCalendar(calendar, commit: true)
    }

    private static func existingCalendar() -> EKCalendar? {
        store.calendars(for: .event).first { $0.title == calendarTitle }
    }

    private static func findOrCreateCalendar() -> EKCalendar? {
        if let existing = existingCalendar() { return existing }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        calendar.cgColor = UIColor(Theme.aegean).cgColor

        // Prefer an iCloud source so the calendar (and its shown/hidden
        // state) follows the user across their own devices, same as
        // Memento's own CloudKit-synced data.
        let source = store.sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
        guard let source else { return nil }
        calendar.source = source

        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            return nil
        }
    }

    /// Full rebuild rather than diffing — simpler and avoids needing to
    /// persist per-date EventKit identifiers back into SwiftData.
    private static func removeAllEvents(in calendar: EKCalendar) {
        let start = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        let end = Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        for event in store.events(matching: predicate) {
            try? store.remove(event, span: .futureEvents, commit: false)
        }
    }

    private static func addYearlyEvent(title: String, date: Date, calendar: EKCalendar) {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = calendar
        event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: date)
        event.endDate = event.startDate
        event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
        try? store.save(event, span: .futureEvents, commit: false)
    }
}
