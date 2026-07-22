import SwiftUI
import SwiftData

/// A month calendar of everyone's birthdays, anniversaries and other
/// important dates. Days show the person's photo (or initials) in a circle;
/// tap a day to see who and what it is.
struct CalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Person.name, comparator: .localizedStandard)]) private var people: [Person]

    @State private var displayedMonth = Date.now
    @AppStorage(AppDateFormat.storageKey) private var dateFormatRaw = AppDateFormat.system.rawValue
    @State private var selectedDay: Int?

    private var calendar: Calendar { .current }

    struct DayEvent: Identifiable {
        let id = UUID()
        let person: Person
        let title: String
        let isBirthday: Bool
        let sourceYear: Int?
    }

    var body: some View {
        // Computed once per render: eventsByDay walks every person's dates,
        // and evaluating it per day cell (31×) plus the selected-day list
        // made month navigation crawl with a few hundred contacts.
        let events = eventsByDay
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    weekdayHeader
                    dayGrid(events)
                    Divider()
                    selectedDaySection(events)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Important Dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: selectTodayIfVisible)
        }
    }

    // MARK: - Month navigation

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal, 4)
    }

    private func shiftMonth(_ delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newMonth
            selectedDay = nil
            selectTodayIfVisible()
        }
    }

    private func selectTodayIfVisible() {
        if calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month) {
            selectedDay = calendar.component(.day, from: .now)
        }
    }

    // MARK: - Grid

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        let ordered = Array(symbols[start...] + symbols[..<start])
        return HStack {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthDays: [Int?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leadingBlanks) + dayRange.map { Optional($0) }
    }

    private func dayGrid(_ events: [Int: [DayEvent]]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, events[day] ?? [])
                } else {
                    Color.clear.frame(height: 54)
                }
            }
        }
    }

    private func dayCell(_ day: Int, _ events: [DayEvent]) -> some View {
        let isSelected = selectedDay == day
        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.footnote.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? AnyShapeStyle(Theme.aegean) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                HStack(spacing: -6) {
                    ForEach(events.prefix(2)) { event in
                        AvatarView(
                            data: event.person.profilePhotoData,
                            name: event.person.name,
                            size: 18,
                            desaturated: event.person.isDeceased,
                            business: event.person.isBusiness
                        )
                    }
                }
                .frame(height: 18)
                if events.count > 2 {
                    Text("+\(events.count - 2)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear.frame(height: 10)
                }
            }
            .frame(height: 54)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Events

    private var eventsByDay: [Int: [DayEvent]] {
        var map: [Int: [DayEvent]] = [:]
        let month = calendar.component(.month, from: displayedMonth)
        // A Feb 29 anniversary's stored day-of-month doesn't exist in the
        // displayed month/year when it isn't a leap year; clamp to the last
        // real day of that month instead of bucketing into a grid cell that
        // was never rendered (dropping the event from the calendar).
        let daysInDisplayedMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 31

        // Ghost nodes (name-only relatives) stay hidden. The self node's
        // dates do show — the My Profile editor accepts them, so dropping
        // them here would silently discard what the user entered. Self rows
        // are labeled "You" and don't navigate (see eventRow): the detail
        // view would expose Delete Person, which cascades away every
        // family-tree edge.
        for person in people where !person.isGhost {
            if let birthday = person.birthday {
                let comps = calendar.dateComponents([.month, .day, .year], from: birthday)
                if comps.month == month, let day = comps.day {
                    map[min(day, daysInDisplayedMonth), default: []].append(DayEvent(
                        person: person,
                        title: "Birthday",
                        isBirthday: true,
                        sourceYear: comps.year
                    ))
                }
            }
            for item in person.importantDatesArray {
                let comps = calendar.dateComponents([.month, .day, .year], from: item.date)
                if comps.month == month, let day = comps.day {
                    map[min(day, daysInDisplayedMonth), default: []].append(DayEvent(
                        person: person,
                        title: item.label,
                        isBirthday: false,
                        sourceYear: comps.year
                    ))
                }
            }
        }
        return map
    }

    private func selectedDaySection(_ eventsByDay: [Int: [DayEvent]]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let day = selectedDay {
                let events = eventsByDay[day] ?? []
                Text(selectedDayTitle(day))
                    .font(.headline)
                if events.isEmpty {
                    Text("No birthdays or important dates on this day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(events) { event in
                            eventRow(event)
                                .padding(.vertical, 8)
                            if event.id != events.last?.id {
                                Divider()
                            }
                        }
                    }
                    .mementoCard(padding: 12)
                }
            } else {
                Text("Select a day to see its birthdays and important dates.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectedDayTitle(_ day: Int) -> String {
        var comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        comps.day = day
        if let date = calendar.date(from: comps) {
            return date.appFormatted(.complete)
        }
        return "Day \(day)"
    }

    @ViewBuilder
    private func eventRow(_ event: DayEvent) -> some View {
        if event.person.isSelf {
            // The self node's row must not open PersonDetailView — it
            // exposes Delete Person, which cascades away every family-tree
            // edge. Your own dates are display-only here; edit them in
            // My Profile.
            eventRowLabel(event)
        } else {
            NavigationLink {
                PersonDetailView(person: event.person)
            } label: {
                eventRowLabel(event)
            }
            .buttonStyle(.plain)
        }
    }

    private func eventRowLabel(_ event: DayEvent) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                data: event.person.profilePhotoData,
                name: event.person.name,
                size: 40,
                desaturated: event.person.isDeceased,
                business: event.person.isBusiness
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(event.person.isSelf ? "You" : event.person.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(eventDetail(event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if event.person.isDeceased {
                Image(systemName: "leaf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if event.isBirthday {
                Text("🎂")
            }
        }
    }

    private func eventDetail(_ event: DayEvent) -> String {
        var detail = event.title
        if event.isBirthday, !event.person.isDeceased,
           let year = event.sourceYear,
           // Year-less imported birthdays carry a placeholder year — any
           // "turns N" from it would be fabricated (e.g. "turns 119" when
           // browsing past months).
           year != Date.placeholderYear {
            let turns = calendar.component(.year, from: displayedMonth) - year
            if turns > 0 && turns < 120 {
                detail += " · turns \(turns)"
            }
        }
        return detail
    }
}
