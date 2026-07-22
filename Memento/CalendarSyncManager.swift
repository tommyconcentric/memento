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
    static let manualSyncOnlyKey = "appleCalendarManualSyncOnly"
    static let lastSyncKey = "appleCalendarLastSync"
    private static let calendarIdentifierKey = "appleCalendarIdentifier"
    // True when the stored identifier points at a calendar this app
    // *adopted* rather than created (see `findOrCreateCalendar`). An
    // adopted calendar may hold the user's own events, so rebuilds touch
    // only app-generated events in it and toggle-off never deletes it.
    private static let calendarAdoptedKey = "appleCalendarAdopted"
    private static let calendarTitle = "Memento"
    // EKEventStore is documented thread-safe; the rebuild runs on syncQueue
    // so a 250-contact full rebuild (measured at multiple seconds) doesn't
    // freeze the UI on every save.
    nonisolated(unsafe) private static let store = EKEventStore()
    nonisolated(unsafe) private static let syncQueue =
        DispatchQueue(label: "brickcedar.Memento.calendar-sync", qos: .utility)
    // Coalescing: a burst of saves bumps the generation; queued rebuilds
    // whose generation is stale skip, so only the newest snapshot lands.
    nonisolated(unsafe) private static var latestGeneration = 0
    nonisolated(unsafe) private static let generationLock = NSLock()

    /// One event to mirror — a plain value, because SwiftData models must
    /// not cross to the sync queue.
    private struct EventSnapshot: Sendable {
        let title: String
        let date: Date
    }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Called from every save site that can change birthdays/important
    /// dates. Respects the user's update-mode choice: in manual-only mode
    /// nothing happens here, and the calendar only changes via "Sync Now"
    /// in Settings (`syncNow`).
    static func refreshFromContext(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: manualSyncOnlyKey) else { return }
        syncNow(context)
    }

    /// Rebuilds the calendar regardless of the auto/manual choice — backs
    /// the "Sync Now" button and the initial population when the sync
    /// toggle is first turned on.
    static func syncNow(_ context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        refresh(people: people)
    }

    /// Snapshots the models on the caller's (main) thread, then hands the
    /// EventKit rebuild to the sync queue.
    static func refresh(people: [Person]) {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }

        var events: [EventSnapshot] = []
        // Ghost nodes (name-only relatives) are excluded, matching the
        // in-app calendar. The hidden self node's dates sync too — the My
        // Profile editor accepts them — titled "Your …" rather than the
        // node's name (which may still be the "You" placeholder).
        for person in people where !person.isDeceased && !person.isGhost {
            if let birthday = person.birthday {
                events.append(EventSnapshot(
                    title: person.isSelf ? "🎂 Your Birthday" : "🎂 \(person.name)'s Birthday",
                    date: birthday
                ))
            }
            for item in person.importantDatesArray {
                events.append(EventSnapshot(
                    title: person.isSelf ? "Your \(item.label)" : "\(item.label) — \(person.name)",
                    date: item.date
                ))
            }
        }

        generationLock.lock()
        latestGeneration += 1
        let generation = latestGeneration
        generationLock.unlock()

        syncQueue.async {
            generationLock.lock()
            let stale = generation != latestGeneration
            generationLock.unlock()
            // A newer snapshot is already queued behind this one.
            guard !stale else { return }
            rebuild(events)
        }
    }

    nonisolated private static func rebuild(_ events: [EventSnapshot]) {
        guard UserDefaults.standard.bool(forKey: enabledKey),
              let calendar = findOrCreateCalendar() else { return }

        removeAllEvents(
            in: calendar,
            onlyAppGenerated: UserDefaults.standard.bool(forKey: calendarAdoptedKey)
        )
        for event in events {
            addYearlyEvent(title: event.title, date: event.date, calendar: calendar)
        }
        try? store.commit()
        // Stored as an epoch interval so Settings can observe it live via
        // @AppStorage (which has no Date overload); written on the main
        // queue so the observation fires where SwiftUI expects.
        DispatchQueue.main.async {
            // A rebuild that raced the off-toggle must not write a fresh
            // timestamp over the zero the off-handler just stored — a
            // nonzero lastSync with no stored identifier re-arms the
            // legacy title-adoption path against calendars this app
            // never created.
            guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: lastSyncKey)
        }
    }

    /// Called when the user turns the sync toggle off. A calendar this app
    /// *created* is deleted outright with everything in it; a calendar it
    /// merely *adopted* (see `findOrCreateCalendar`) belongs to the user,
    /// so only the app-generated events are stripped and the calendar
    /// itself stays. Either way only the calendar whose identifier this
    /// app stored is ever touched; acting by title could destroy a user's
    /// own calendar that happens to share the name.
    static func removeCalendar() {
        // Invalidate queued rebuilds, then run the removal ON the sync
        // queue so it serializes behind any rebuild already executing —
        // removing from the main thread mid-rebuild let the rebuild
        // recreate and repopulate a zombie calendar after the toggle was
        // already off.
        generationLock.lock()
        latestGeneration += 1
        generationLock.unlock()
        syncQueue.async {
            guard let calendar = existingCalendar() else { return }
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: calendarAdoptedKey) {
                removeAllEvents(in: calendar, onlyAppGenerated: true)
                do {
                    try store.commit()
                    defaults.removeObject(forKey: calendarIdentifierKey)
                    defaults.removeObject(forKey: calendarAdoptedKey)
                } catch {
                    // Keep both keys so a retry still knows which calendar
                    // holds this app's events — and that it must never be
                    // deleted.
                }
            } else {
                do {
                    try store.removeCalendar(calendar, commit: true)
                    defaults.removeObject(forKey: calendarIdentifierKey)
                    defaults.removeObject(forKey: calendarAdoptedKey)
                } catch {
                    // Removal can fail (e.g. Calendar access was revoked).
                    // Keep the identifier so re-enabling sync — or a later
                    // toggle-off — still targets the real calendar instead
                    // of stranding it in the user's account forever.
                }
            }
        }
    }

    /// Resolves the app's calendar by its persisted identifier. Falls back
    /// to a one-time title match only when a previous version already
    /// synced (lastSync > 0) before identifiers were stored — for those
    /// installs the same-titled calendar is the one this app created. A
    /// fresh setup never adopts here, so a toggle-off can't remove a
    /// calendar this app never claimed; *enabling* sync adopts via
    /// `findOrCreateCalendar`'s source-restricted title match instead.
    nonisolated private static func existingCalendar() -> EKCalendar? {
        let defaults = UserDefaults.standard
        if let identifier = defaults.string(forKey: calendarIdentifierKey) {
            return store.calendar(withIdentifier: identifier)
        }
        guard defaults.double(forKey: lastSyncKey) > 0,
              let legacy = store.calendars(for: .event).first(where: { $0.title == calendarTitle })
        else { return nil }
        defaults.set(legacy.calendarIdentifier, forKey: calendarIdentifierKey)
        return legacy
    }

    nonisolated private static func findOrCreateCalendar() -> EKCalendar? {
        if let existing = existingCalendar() { return existing }

        // Prefer an iCloud source so the calendar (and its shown/hidden
        // state) follows the user across their own devices, same as
        // Memento's own CloudKit-synced data.
        let source = store.sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
        guard let source else { return nil }

        // The stored identifier is device-local (UserDefaults), but the
        // calendar itself lives in the iCloud source precisely so it
        // reaches all of the user's devices — so a second device (or this
        // one after a reinstall) has no identifier while the calendar
        // already exists. Adopt a same-titled writable calendar from the
        // source we would create in, rather than standing up a duplicate
        // "Memento" beside it that every device then maintains in
        // parallel. Restricting adoption to that one source keeps this
        // away from same-titled calendars in other accounts — and because
        // the adopted calendar could still be one the *user* made by hand,
        // it's marked adopted: rebuilds then remove only app-generated
        // events from it (`isAppGeneratedTitle`) and toggle-off strips
        // those events instead of deleting the calendar.
        if let adopted = store.calendars(for: .event).first(where: {
            $0.title == calendarTitle
                && $0.source?.sourceIdentifier == source.sourceIdentifier
                && $0.allowsContentModifications
        }) {
            UserDefaults.standard.set(adopted.calendarIdentifier, forKey: calendarIdentifierKey)
            UserDefaults.standard.set(true, forKey: calendarAdoptedKey)
            return adopted
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        // Theme.aegean's components inlined: Theme statics are
        // main-actor-isolated and this runs on the sync queue.
        calendar.cgColor = UIColor(red: 0.118, green: 0.431, blue: 0.624, alpha: 1).cgColor
        calendar.source = source

        do {
            try store.saveCalendar(calendar, commit: true)
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIdentifierKey)
            // A calendar this app minted is provably its own — full-window
            // rebuilds and delete-on-toggle-off apply.
            UserDefaults.standard.removeObject(forKey: calendarAdoptedKey)
            return calendar
        } catch {
            return nil
        }
    }

    /// Whether an event title has one of the exact shapes this manager
    /// writes (see the snapshot loop in `refresh` — update this list
    /// alongside any title format change):
    ///   "🎂 <name>'s Birthday"     — someone's birthday
    ///   "🎂 Your Birthday"         — the self node's birthday
    ///   "<label> — <name>"         — someone's important date (em dash)
    ///   "Your <label>"             — a self important date
    /// Scopes removals in an *adopted* calendar to app-generated events;
    /// everything else in such a calendar is the user's own content.
    nonisolated private static func isAppGeneratedTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        if title == "🎂 Your Birthday" { return true }
        if title.hasPrefix("🎂 ") && title.hasSuffix("'s Birthday") { return true }
        if title.hasPrefix("Your ") { return true }
        if title.contains(" — ") { return true }
        return false
    }

    /// Full rebuild rather than diffing — simpler and avoids needing to
    /// persist per-date EventKit identifiers back into SwiftData. In an
    /// adopted calendar (`onlyAppGenerated`) the wipe is scoped to titles
    /// this app writes; a calendar the app created is cleared wholesale.
    nonisolated private static func removeAllEvents(in calendar: EKCalendar, onlyAppGenerated: Bool) {
        // EventKit silently truncates an events predicate to four years
        // from its start date, so one six-year predicate would stop
        // matching at now+3y — leaving the Feb-29 branch's far-future
        // concrete events (out to ~4.6 years ahead) unmatched and
        // re-added as one more duplicate on every rebuild. Walk the
        // window in three-year chunks so every span stays under the cap.
        let end = Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now
        var chunkStart = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        while chunkStart < end {
            let chunkEnd = min(Calendar.current.date(byAdding: .year, value: 3, to: chunkStart) ?? end, end)
            let predicate = store.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: [calendar])
            for event in store.events(matching: predicate) {
                if onlyAppGenerated && !isAppGeneratedTitle(event.title) { continue }
                // A recurring series can surface occurrences in more than
                // one chunk (removals are uncommitted until the rebuild's
                // single commit); re-removing just throws, and is swallowed.
                try? store.remove(event, span: .futureEvents, commit: false)
            }
            chunkStart = chunkEnd
        }
    }

    nonisolated private static func addYearlyEvent(title: String, date: Date, calendar: EKCalendar) {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        if components.month == 2, components.day == 29 {
            // A single yearly series can't render Feb 29 dates correctly:
            // anchored on Feb 29 it skips non-leap years entirely, and
            // anchored on a Feb 28 fallback it stays on Feb 28 forever,
            // including leap years where the real date exists. Emit one
            // concrete event per year across the rebuild window instead
            // (Feb 29 in leap years, Feb 28 otherwise), refreshed on every
            // sync like everything else.
            let thisYear = Calendar.current.component(.year, from: .now)
            // Only emit occurrences inside removeAllEvents' one-year
            // lookback: last year's date can fall before that window (Feb
            // 28, 2025 against a July 2026 rebuild), where no rebuild could
            // ever remove it — every sync would then stack one more
            // duplicate onto the user's calendar, forever.
            let windowStart = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
            for year in (thisYear - 1)...(thisYear + 4) {
                guard let day = occurrence(month: 2, day: 29, inYear: year),
                      day >= windowStart else { continue }
                addSingleEvent(title: title, on: day, calendar: calendar)
            }
            return
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = calendar
        event.isAllDay = true
        event.startDate = recentAnchor(for: date)
        event.endDate = event.startDate
        event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
        try? store.save(event, span: .futureEvents, commit: false)
    }

    nonisolated private static func addSingleEvent(title: String, on date: Date, calendar: EKCalendar) {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = calendar
        event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: date)
        event.endDate = event.startDate
        try? store.save(event, span: .thisEvent, commit: false)
    }

    /// The concrete date of a month/day in a given year; Feb 29 falls back
    /// to Feb 28 in non-leap years, matching Date.daysUntilNextOccurrence.
    nonisolated private static func occurrence(month: Int, day: Int, inYear year: Int) -> Date? {
        let calendar = Calendar.current
        var comps = DateComponents(year: year, month: month, day: day)
        if month == 2, day == 29,
           let feb1 = calendar.date(from: DateComponents(year: year, month: 2, day: 1)),
           calendar.range(of: .day, in: .month, for: feb1)?.count != 29 {
            comps.day = 28
        }
        return calendar.date(from: comps)
    }

    /// A recurring event's DTSTART only ever generates occurrences on or
    /// after itself, so anchoring at the literal stored year (e.g. a 1990
    /// birthday) puts decades of past occurrences outside
    /// `removeAllEvents`'s one-year lookback window. On every later
    /// refresh, that old series survives untouched while a brand-new one is
    /// created alongside it, leaking a duplicate on each date that already
    /// occurred before the window's start. Anchoring at the most recent
    /// occurrence (this year's if it's already passed, else last year's)
    /// keeps the anchor inside the lookback window on every future refresh,
    /// so the old series is always found and replaced instead of leaking.
    nonisolated private static func recentAnchor(for date: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else {
            return calendar.startOfDay(for: date)
        }
        let todayYear = calendar.component(.year, from: today)

        guard let thisYear = occurrence(month: month, day: day, inYear: todayYear) else {
            return calendar.startOfDay(for: date)
        }
        let mostRecent = thisYear <= today
            ? thisYear
            : (occurrence(month: month, day: day, inYear: todayYear - 1) ?? thisYear)
        return calendar.startOfDay(for: mostRecent)
    }
}
