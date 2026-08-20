import SwiftUI
import CloudKit
import Charts

/// The developer's hidden usage dashboard: aggregates the anonymous
/// `UsagePing` records from the app's public CloudKit database into
/// daily actives, sessions and contacts-created. Opened by tapping the
/// version line in Settings seven times. It is hidden on purpose but not
/// gated, because everything it shows is anonymous aggregate data from
/// the world-readable public database.
///
/// Downloads are NOT here: the app can't measure its own installs.
/// That number lives in App Store Connect → Analytics.
struct UsageDashboardView: View {
    @Environment(\.dismiss) private var dismiss

    private enum DayRange: Int, CaseIterable {
        case week = 7, month = 30, quarter = 90
        var label: String { "\(rawValue) days" }
    }

    private struct DailyUsage: Identifiable {
        let day: Date
        var actives = 0
        var sessions = 0
        var contactsCreated = 0
        var id: Date { day }
    }

    private enum LoadState {
        case loading
        case loaded
        case failed(String)
    }

    @State private var range: DayRange = .month
    @State private var state: LoadState = .loading
    @State private var days: [DailyUsage] = []
    @State private var distinctInstalls = 0
    // One selection per chart. Charts clears it when the finger lifts.
    @State private var selectedActivesDay: Date?
    @State private var selectedSessionsDay: Date?
    @State private var selectedContactsDay: Date?

    // Marks keep ≥3:1 against both card surfaces; aegean alone drops to
    // 2.7:1 on the dark card, so dark mode steps up to sky. That is a
    // chosen lighter step of the same hue, not an automatic flip.
    private let activesColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.310, green: 0.651, blue: 0.835, alpha: 1)   // Theme.sky
            : UIColor(red: 0.118, green: 0.431, blue: 0.624, alpha: 1)   // Theme.aegean
    })
    private let sessionsColor = Theme.terracotta
    private let contactsColor = Theme.olive

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PillPicker(
                        selection: $range,
                        options: DayRange.allCases.map { ($0, $0.label) }
                    )

                    switch state {
                    case .loading:
                        ProgressView("Loading usage data…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    case .failed(let message):
                        ContentUnavailableView {
                            Label("Couldn't Load Usage Data", systemImage: "chart.bar.xaxis")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Retry") { reload() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 40)
                    case .loaded:
                        if days.allSatisfy({ $0.actives == 0 }) {
                            ContentUnavailableView {
                                Label("No Pings Yet", systemImage: "chart.bar.xaxis")
                            } description: {
                                Text("No usage pings in this window. Debug builds read CloudKit's development environment. TestFlight and App Store installs report into production.")
                            }
                            .padding(.top, 40)
                        } else {
                            summaryTiles
                            chartCard(
                                title: "Active installs",
                                subtitle: "installs that opened Memento each day",
                                color: activesColor,
                                selection: $selectedActivesDay,
                                value: \.actives
                            )
                            chartCard(
                                title: "Sessions",
                                subtitle: "app opens, 30-minute gap = new session",
                                color: sessionsColor,
                                selection: $selectedSessionsDay,
                                value: \.sessions
                            )
                            chartCard(
                                title: "Contacts created",
                                subtitle: "new people added by hand or import",
                                color: contactsColor,
                                selection: $selectedContactsDay,
                                value: \.contactsCreated
                            )
                        }
                        footnotes
                    }
                }
                .padding()
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    // Chart preview without network or pings. Dev only,
                    // same spirit as StressSeeder.
                    Button("Sample") { loadSampleData() }
                }
                #endif
            }
            .task(id: range) { reload() }
        }
    }

    // MARK: - Summary

    private var windowSessions: Int { days.reduce(0) { $0 + $1.sessions } }
    private var windowContacts: Int { days.reduce(0) { $0 + $1.contactsCreated } }
    private var activesToday: Int {
        days.last(where: { Calendar.current.isDateInToday($0.day) })?.actives ?? 0
    }

    private var summaryTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(value: activesToday, caption: "active today")
            statTile(value: distinctInstalls, caption: "installs seen in \(range.label)")
            statTile(value: windowSessions, caption: "sessions in \(range.label)")
            statTile(value: windowContacts, caption: "contacts created in \(range.label)")
        }
    }

    private func statTile(value: Int, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(.title, design: .serif).weight(.semibold))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mementoCard()
    }

    // MARK: - Charts

    private func chartCard(title: String, subtitle: String, color: Color,
                           selection: Binding<Date?>, value: KeyPath<DailyUsage, Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.headline, design: .serif))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // The "tooltip": drag across the bars and the header shows
                // that day's value in ink, not in the series color.
                if let selected = selection.wrappedValue,
                   let match = days.first(where: { Calendar.current.isDate($0.day, inSameDayAs: selected) }) {
                    Text("\(match.day.appFormattedMonthDay()) · \(match[keyPath: value])")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            Chart(days) { usage in
                BarMark(
                    x: .value("Day", usage.day, unit: .day),
                    y: .value(title, usage[keyPath: value])
                )
                .foregroundStyle(color)
                .cornerRadius(3)
            }
            .chartXSelection(value: selection)
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel().font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, range.rawValue / 6))) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mementoCard()
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The app can't count downloads. Check App Store Connect → Analytics for installs and store metrics.")
            Text("Counts are anonymous daily pings (random install id, sessions, contacts created) from installs sharing usage statistics. Debug builds read CloudKit's development environment.")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Data

    private func reload() {
        state = .loading
        Task {
            do {
                try await fetch()
                state = .loaded
            } catch let error as CKError where error.code == .notAuthenticated {
                state = .failed("Sign into iCloud on this device to read the public usage database.")
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func fetch() async throws {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: end) else { return }

        let database = CKContainer(identifier: "iCloud.brickcedar.Memento").publicCloudDatabase
        let query = CKQuery(
            recordType: "UsagePing",
            predicate: NSPredicate(format: "pingDate >= %@", start as NSDate)
        )

        var records: [CKRecord] = []
        var page = try await database.records(matching: query, resultsLimit: 400)
        records += page.matchResults.compactMap { try? $0.1.get() }
        while let cursor = page.queryCursor {
            page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 400)
            records += page.matchResults.compactMap { try? $0.1.get() }
        }

        var byDay: [Date: DailyUsage] = [:]
        var installs: Set<String> = []
        for record in records {
            guard let pingDate = record["pingDate"] as? Date else { continue }
            let day = calendar.startOfDay(for: pingDate)
            guard day >= start else { continue }
            var usage = byDay[day] ?? DailyUsage(day: day)
            usage.actives += 1
            usage.sessions += (record["sessions"] as? Int) ?? 0
            usage.contactsCreated += (record["contactsCreated"] as? Int) ?? 0
            byDay[day] = usage
            if let install = record["installID"] as? String {
                installs.insert(install)
            }
        }

        // A continuous axis: zero-filled days keep gaps visible as gaps.
        var series: [DailyUsage] = []
        var cursor = start
        while cursor <= end {
            series.append(byDay[cursor] ?? DailyUsage(day: cursor))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }

        days = series
        distinctInstalls = installs.count
    }

    #if DEBUG
    /// Deterministic fake series so the charts can be previewed (and the
    /// screen verified) without network, an iCloud account, or real pings.
    private func loadSampleData() {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        var series: [DailyUsage] = []
        for offset in stride(from: range.rawValue - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let base = 18 + (offset * 7) % 11
            let weekendDip = (weekday == 1 || weekday == 7) ? 6 : 0
            let actives = max(2, base - weekendDip)
            series.append(DailyUsage(
                day: day,
                actives: actives,
                sessions: actives * 2 + (offset * 3) % 9,
                contactsCreated: max(0, (offset * 5) % 13 - 4)
            ))
        }
        days = series
        distinctInstalls = 47
        state = .loaded
    }
    #endif
}
