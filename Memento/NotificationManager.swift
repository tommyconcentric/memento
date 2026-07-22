import Foundation
import SwiftData
import UserNotifications

/// Schedules yearly 9 AM local notifications for birthdays and important
/// dates. iOS caps pending local notifications at 64, so the nearest 60
/// upcoming dates are scheduled; the list refreshes whenever data changes.
enum NotificationManager {
    static let enabledKey = "birthdayRemindersEnabled"

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func refreshFromContext(_ context: ModelContext) {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        refresh(people: people)
    }

    static func refresh(people: [Person]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }

        struct PendingEvent {
            let title: String
            let body: String
            let date: Date
            let daysAway: Int
        }

        var events: [PendingEvent] = []
        // Ghost nodes (name-only relatives) are skipped. So is the self
        // node's *birthday* — it would notify "It's <your name>'s birthday
        // — send them a message!" at yourself — but the important dates the
        // My Profile editor accepts do remind, phrased as "Your …" rather
        // than addressing you by name.
        for person in people where !person.isDeceased && !person.isGhost {
            if let birthday = person.birthday, person.birthdayReminderEnabled, !person.isSelf {
                events.append(PendingEvent(
                    title: "🎂 \(person.name)'s birthday",
                    body: "It's \(person.name)'s birthday today — send them a message!",
                    date: birthday,
                    daysAway: Date.daysUntilNextOccurrence(of: birthday) ?? Int.max
                ))
            }
            for item in person.importantDatesArray where item.remindersEnabled {
                events.append(PendingEvent(
                    title: "📅 \(item.label)",
                    body: person.isSelf
                        ? "Your \(item.label) is today."
                        : "\(item.label) for \(person.name) is today.",
                    date: item.date,
                    daysAway: Date.daysUntilNextOccurrence(of: item.date) ?? Int.max
                ))
            }
        }

        for event in events.sorted(by: { $0.daysAway < $1.daysAway }).prefix(60) {
            var components = Calendar.current.dateComponents([.month, .day], from: event.date)
            let trigger: UNCalendarNotificationTrigger
            if components.month == 2, components.day == 29,
               var next = Date.nextOccurrence(of: event.date) {
                // A repeating trigger matches one fixed month/day forever:
                // a literal Feb 29 would skip non-leap years, and a Feb 28
                // remap would fire a day early in leap years. Aim a one-shot
                // at the actual next occurrence (Feb 29 in leap years,
                // Feb 28 otherwise) — the refresh on every save re-arms it.
                if let nineAM = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: next),
                   nineAM <= .now {
                    // nextOccurrence returns *today* on the day itself; a
                    // one-shot aimed at a 9 AM already past never fires, so
                    // a refresh that afternoon would silently disarm next
                    // year's reminder. Aim at the following year instead.
                    let year = Calendar.current.component(.year, from: next) + 1
                    var comps = DateComponents(year: year, month: 2, day: 29)
                    if let feb1 = Calendar.current.date(from: DateComponents(year: year, month: 2, day: 1)),
                       Calendar.current.range(of: .day, in: .month, for: feb1)?.count != 29 {
                        comps.day = 28
                    }
                    next = Calendar.current.date(from: comps) ?? next
                }
                var oneShot = Calendar.current.dateComponents([.year, .month, .day], from: next)
                oneShot.hour = 9
                trigger = UNCalendarNotificationTrigger(dateMatching: oneShot, repeats: false)
            } else {
                components.hour = 9
                trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            }
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            center.add(UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: trigger
            ))
        }
    }
}
