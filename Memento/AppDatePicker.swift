import SwiftUI

/// Memento's own date picker. The native compact picker hides day
/// selection behind a tap on the month label; here month, year and day
/// are all visible and directly adjustable at once — chevrons step,
/// tapping the month or year label opens an explicit menu, and the day
/// grid is always on screen. Personal wears the serif/aegean voice,
/// business the sans/graphite one.
struct AppDatePicker: View {
    let title: String
    @Binding var date: Date
    var business = false

    @State private var isExpanded: Bool

    init(title: String, date: Binding<Date>, business: Bool = false, initiallyExpanded: Bool = false) {
        self.title = title
        self._date = date
        self.business = business
        self._isExpanded = State(initialValue: initiallyExpanded)
    }

    private var calendar: Calendar { .current }
    private var accent: Color { business ? Theme.graphite : Theme.aegean }
    private var fontDesign: Font.Design { business ? .default : .serif }
    private var plateTint: Color { business ? Theme.steel.opacity(0.08) : Theme.gold.opacity(0.07) }

    private var year: Int { calendar.component(.year, from: date) }
    private var month: Int { calendar.component(.month, from: date) }
    private var day: Int { calendar.component(.day, from: date) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(date.appFormatted())
                        .foregroundStyle(accent)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                calendarBody
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Calendar

    private var calendarBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                stepper(icon: "chevron.left") { shift(.month, by: -1) }
                Menu {
                    ForEach(Array(calendar.monthSymbols.enumerated()), id: \.offset) { index, name in
                        Button(name) { set(month: index + 1) }
                    }
                } label: {
                    menuLabel(calendar.monthSymbols[month - 1])
                }
                stepper(icon: "chevron.right") { shift(.month, by: 1) }

                Spacer(minLength: 12)

                stepper(icon: "chevron.left") { shift(.year, by: -1) }
                Menu {
                    // Recent years first — birthdays live decades back.
                    ForEach(yearOptions, id: \.self) { option in
                        Button(String(option)) { set(year: option) }
                    }
                } label: {
                    menuLabel(String(year))
                }
                stepper(icon: "chevron.right") { shift(.year, by: 1) }
            }

            weekdayHeader
            dayGrid
        }
        .padding(10)
        .background(plateTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var yearOptions: [Int] {
        let thisYear = calendar.component(.year, from: .now)
        return Array((1900...(thisYear + 10)).reversed())
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.system(.subheadline, design: fontDesign, weight: .semibold))
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    private func stepper(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

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

    private var dayGrid: some View {
        let today = calendar.dateComponents([.year, .month, .day], from: .now)
        let isThisMonth = today.year == year && today.month == month
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, gridDay in
                if let gridDay {
                    let isSelected = gridDay == day
                    Button {
                        set(day: gridDay)
                    } label: {
                        Text("\(gridDay)")
                            .font(.footnote.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                isSelected ? accent : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay {
                                if isThisMonth && gridDay == today.day && !isSelected {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(height: 32)
                }
            }
        }
    }

    private var gridDays: [Int?] {
        guard let first = calendar.date(from: DateComponents(year: year, month: month)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: first)
        let blanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: blanks) + range.map(Optional.init)
    }

    // MARK: - Mutation (day clamps when the target month is shorter)

    private func set(day newDay: Int) {
        if let updated = calendar.date(from: DateComponents(year: year, month: month, day: newDay)) {
            date = updated
        }
    }

    private func set(month newMonth: Int) {
        apply(year: year, month: newMonth)
    }

    private func set(year newYear: Int) {
        apply(year: newYear, month: month)
    }

    private func shift(_ component: Calendar.Component, by value: Int) {
        guard let shifted = calendar.date(byAdding: component, value: value, to: date) else { return }
        date = shifted
    }

    private func apply(year newYear: Int, month newMonth: Int) {
        guard let first = calendar.date(from: DateComponents(year: newYear, month: newMonth)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return }
        let clampedDay = min(day, range.count)
        if let updated = calendar.date(from: DateComponents(year: newYear, month: newMonth, day: clampedDay)) {
            date = updated
        }
    }
}
