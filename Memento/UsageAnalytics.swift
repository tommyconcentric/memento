import Foundation
import CloudKit
import UIKit
import OSLog

/// Anonymous usage statistics: a random install identifier, a day, how many
/// times the app was opened and how many contacts were created that day.
/// Never a name, note, photo, date or anything else the user typed.
/// Never any identifier tied to them or their iCloud account.
///
/// Pings land in the app's CloudKit *public* database (one `UsagePing`
/// record per install per day) where the developer reads aggregate totals;
/// the hidden usage dashboard (see `UsageDashboardView`) does exactly that.
/// This deliberately does not touch SwiftData or the private database, so
/// the user's own data and its sync are never entangled with analytics.
///
/// The Settings toggle ("Share anonymous usage statistics", on by default)
/// gates every send; switching it off also deletes the pings this install
/// already sent (best effort, since it needs a network and an iCloud
/// account, like the sends themselves).
@MainActor
enum UsageAnalytics {
    /// Stored inverted ("opt out") so the default `false` means sharing is
    /// on without a migration writing defaults on first launch.
    static let optOutKey = "usageStatsOptOut"

    private static let installIDKey = "usageInstallID"
    private static let lastSeenKey = "usageLastSeenAt"
    private static let pendingKey = "usagePendingDays"
    private static let recordType = "UsagePing"
    /// A reopen within this window is the same visit, not a new session.
    /// That matters on the Mac, where every window focus reactivates the
    /// scene.
    private static let sessionGap: TimeInterval = 30 * 60
    /// Days kept locally while waiting for a successful upload. An install
    /// that can never upload (no iCloud account) stops accumulating here
    /// instead of growing UserDefaults forever.
    private static let maxPendingDays = 30

    private static let logger = Logger(subsystem: "brickcedar.Memento", category: "usage")
    private static var flushTask: Task<Void, Never>?

    struct DayCounters: Codable {
        var sessions = 0
        var contactsCreated = 0
        /// Cleared once the day's totals reach CloudKit; set again by any
        /// later change to the same day.
        var dirty = true
    }

    static var isEnabled: Bool {
        !UserDefaults.standard.bool(forKey: optOutKey)
    }

    /// Random, minted once per install, never derived from the user or
    /// device. It distinguishes "30 opens by one person" from "30 people",
    /// and nothing more.
    static var installID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: installIDKey) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: installIDKey)
        return fresh
    }

    // MARK: - Recording

    /// Called on every scene activation. Counts a session only when the
    /// last sighting is more than `sessionGap` ago, so window focus and
    /// the Face ID dialog's active/inactive dips never inflate the count.
    static func appBecameActive() {
        guard isEnabled else { return }
        let defaults = UserDefaults.standard
        let lastSeen = defaults.object(forKey: lastSeenKey) as? Date
        defaults.set(Date.now, forKey: lastSeenKey)
        if let lastSeen, Date.now.timeIntervalSince(lastSeen) < sessionGap {
            return
        }
        mutateToday { $0.sessions += 1 }
        scheduleFlush()
    }

    /// Keeps the last-seen stamp honest across long foreground stretches,
    /// so a quick return after backgrounding isn't miscounted as new.
    static func appLeftForeground() {
        guard isEnabled else { return }
        UserDefaults.standard.set(Date.now, forKey: lastSeenKey)
        scheduleFlush()
    }

    /// Real contacts the user added: editor saves and imports. Ghost
    /// relatives and the hidden self node never come through here.
    static func recordContactsCreated(_ count: Int) {
        guard isEnabled, count > 0 else { return }
        mutateToday { $0.contactsCreated += count }
        scheduleFlush()
    }

    /// The Settings toggle's off-handler: stop everything, forget what was
    /// queued, and (best effort) remove what this install already sent.
    static func handleOptOut() {
        flushTask?.cancel()
        flushTask = nil
        UserDefaults.standard.removeObject(forKey: pendingKey)
        Task { await deleteRemotePings() }
    }

    // MARK: - Local counters

    private static func day(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private static func loadPending() -> [String: DayCounters] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let decoded = try? JSONDecoder().decode([String: DayCounters].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func savePending(_ pending: [String: DayCounters]) {
        var bounded = pending
        // Oldest days fall off first once over the cap; today survives.
        let overflow = bounded.count - maxPendingDays
        if overflow > 0 {
            for key in bounded.keys.sorted().prefix(overflow) {
                bounded.removeValue(forKey: key)
            }
        }
        if let data = try? JSONEncoder().encode(bounded) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }

    private static func mutateToday(_ change: (inout DayCounters) -> Void) {
        var pending = loadPending()
        let today = day(for: .now)
        var counters = pending[today] ?? DayCounters()
        change(&counters)
        counters.dirty = true
        pending[today] = counters
        savePending(pending)
    }

    // MARK: - Upload

    private static var database: CKDatabase {
        CKContainer(identifier: "iCloud.brickcedar.Memento").publicCloudDatabase
    }

    /// Coalesces bursts (activation + a contact save moments later) into
    /// one upload pass.
    private static func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    static func flush() async {
        guard isEnabled else { return }
        var pending = loadPending()
        let dirtyDays = pending.filter(\.value.dirty).keys.sorted()
        guard !dirtyDays.isEmpty else { return }

        for dayKey in dirtyDays {
            guard let counters = pending[dayKey] else { continue }
            do {
                try await upsert(dayKey: dayKey, counters: counters)
                pending[dayKey]?.dirty = false
            } catch {
                // Offline, no iCloud account, rate limited. The counters
                // stay dirty and the next flush retries. Never user-facing.
                logger.info("usage flush deferred for \(dayKey, privacy: .public): \(error.localizedDescription, privacy: .public)")
                break
            }
        }

        // Uploaded history has no further use locally; keep a short tail
        // (today may still be re-dirtied) and drop the rest.
        let today = day(for: .now)
        for (key, counters) in pending where key != today && !counters.dirty {
            pending.removeValue(forKey: key)
        }
        savePending(pending)
    }

    /// One record per install per day, named deterministically so repeated
    /// uploads of the same day overwrite rather than duplicate. The fields
    /// are absolute day totals, so overwriting is always safe.
    private static func upsert(dayKey: String, counters: DayCounters) async throws {
        let recordID = CKRecord.ID(recordName: "\(installID)|\(dayKey)")
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        record["installID"] = installID
        record["day"] = dayKey
        record["pingDate"] = pingDate(from: dayKey)
        record["sessions"] = counters.sessions
        record["contactsCreated"] = counters.contactsCreated
        record["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        record["platform"] = platform
        _ = try await database.save(record)
        logger.info("usage ping saved for \(dayKey, privacy: .public)")
    }

    private static func pingDate(from dayKey: String) -> Date {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .now }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? .now
    }

    private static var platform: String {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "mac" }
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    /// Opt-out cleanup: remove every ping this install ever sent. Needs the
    /// `installID` field to be queryable (see the CloudKit schema note in
    /// CLAUDE.md). Failures are logged and swallowed. The opt-out itself
    /// (no further sends) never depends on this succeeding.
    private static func deleteRemotePings() async {
        do {
            let query = CKQuery(
                recordType: recordType,
                predicate: NSPredicate(format: "installID == %@", installID)
            )
            var cursor: CKQueryOperation.Cursor?
            var ids: [CKRecord.ID] = []
            let first = try await database.records(matching: query, resultsLimit: 200)
            ids += first.matchResults.map(\.0)
            cursor = first.queryCursor
            while let next = cursor {
                let page = try await database.records(continuingMatchFrom: next, resultsLimit: 200)
                ids += page.matchResults.map(\.0)
                cursor = page.queryCursor
            }
            for id in ids {
                try await database.deleteRecord(withID: id)
            }
            logger.info("usage opt-out removed \(ids.count) pings")
        } catch {
            logger.info("usage opt-out cleanup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
