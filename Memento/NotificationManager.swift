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
        // Skip hidden graph nodes — the self node would otherwise notify
        // "It's <your name>'s birthday — send them a message!" at yourself.
        for person in people where !person.isDeceased && !person.isSelf && !person.isGhost {
            if let birthday = person.birthday, person.birthdayReminderEnabled {
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
                    body: "\(item.label) for \(person.name) is today.",
                    date: item.date,
                    daysAway: Date.daysUntilNextOccurrence(of: item.date) ?? Int.max
                ))
            }
        }

        for event in events.sorted(by: { $0.daysAway < $1.daysAway }).prefix(60) {
            var components = Calendar.current.dateComponents([.month, .day], from: event.date)
            let trigger: UNCalendarNotificationTrigger
            if components.month == 2, components.day == 29,
               let next = Date.nextOccurrence(of: event.date) {
                // A repeating trigger matches one fixed month/day forever:
                // a literal Feb 29 would skip non-leap years, and a Feb 28
                // remap would fire a day early in leap years. Aim a one-shot
                // at the actual next occurrence (Feb 29 in leap years,
                // Feb 28 otherwise) — the refresh on every save re-arms it.
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
