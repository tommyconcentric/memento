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
    // When a caller passes `expanded`, the header's collapse/expand writes
    // through to the caller's state instead of the private one — the
    // editor's year-less birthday row needs to know when the calendar
    // closes so it can take the header's place back.
    private var externalExpanded: Binding<Bool>?
    // The day grid's measured width, so its numbers and gutters size to the
    // space they actually get (see MonthGridMetrics).
    @State private var gridWidth: CGFloat = 0

    init(title: String, date: Binding<Date>, business: Bool = false,
         initiallyExpanded: Bool = false, expanded: Binding<Bool>? = nil) {
        self.title = title
        self._date = date
        self.business = business
        self._isExpanded = State(initialValue: initiallyExpanded)
        self.externalExpanded = expanded
    }

    private var expandedNow: Bool {
        externalExpanded?.wrappedValue ?? isExpanded
    }

    private func toggleExpanded() {
        withAnimation(.snappy(duration: 0.22)) {
            if let externalExpanded {
                externalExpanded.wrappedValue.toggle()
            } else {
                isExpanded.toggle()
            }
        }
    }

    /// The picker runs in the device calendar so its numbers agree with the
    /// header row and the rest of the app — Buddhist (year 2569) and Hebrew
    /// (5786) devices work natively. But a calendar whose current year sits
    /// below the year menu's 1900 floor (Japanese ≈ Reiwa 8, Republic of
    /// China ≈ 115, Persian ≈ 1405, Islamic ≈ 1447) would invert the
    /// `1900...` range and trap; those fall back to Gregorian arithmetic
    /// (keeping locale, time zone and week start) — same defense as
    /// `Date.gregorian` in Utilities — turning a guaranteed crash into
    /// Gregorian year numbering.
    private var calendar: Calendar {
        let current = Calendar.current
        if current.component(.year, from: .now) >= 1900 { return current }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = current.locale
        gregorian.timeZone = current.timeZone
        gregorian.firstWeekday = current.firstWeekday
        return gregorian
    }
    private var accent: Color { business ? Theme.graphite : Theme.aegean }
    private var fontDesign: Font.Design { business ? .default : .serif }
    private var plateTint: Color { business ? Theme.steel.opacity(0.08) : Theme.gold.opacity(0.07) }

    private var year: Int { calendar.component(.year, from: date) }
    private var month: Int { calendar.component(.month, from: date) }
    private var day: Int { calendar.component(.day, from: date) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                toggleExpanded()
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
                        .rotationEffect(.degrees(expandedNow ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedNow {
                calendarBody
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Calendar

    private var calendarBody: some View {
        VStack(spacing: 12) {
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
        .padding(12)
        .background(plateTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Grow with the form up to a tidy width, then centre — on a wide
        // Mac editor the plate would otherwise splay the numbers apart.
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    private var yearOptions: [Int] {
        // Belt and braces: never build an inverted range even if the
        // calendar's year math ever surprises again.
        let thisYear = calendar.component(.year, from: .now)
        return Array((1900...max(thisYear + 10, 1900)).reversed())
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
        // Same gutter as the grid below so the initials sit over their days.
        let spacing = MonthGridMetrics(availableWidth: gridWidth).spacing
        return HStack(spacing: spacing) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let today = calendar.dateComponents([.year, .month, .day], from: .now)
        let isThisMonth = today.year == year && today.month == month
        let metrics = MonthGridMetrics(availableWidth: gridWidth)
        // Half the cell width, clamped legible→large; the row runs a touch
        // shorter than it is wide, and the chip corner scales with it.
        let fontSize = metrics.fontSize(fraction: 0.5, in: 17...30)
        let rowHeight = (metrics.cellWidth * 0.92).clamped(to: 36...56)
        let corner = (metrics.cellWidth * 0.26).clamped(to: 9...16)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: metrics.spacing), count: 7),
            spacing: metrics.spacing
        ) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, gridDay in
                if let gridDay {
                    let isSelected = gridDay == day
                    Button {
                        set(day: gridDay)
                    } label: {
                        Text("\(gridDay)")
                            .font(.system(size: fontSize, weight: isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                            .background(
                                isSelected ? accent : Color.clear,
                                in: RoundedRectangle(cornerRadius: corner, style: .continuous)
                            )
                            .overlay {
                                if isThisMonth && gridDay == today.day && !isSelected {
                                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                                        .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(height: rowHeight)
                }
            }
        }
        .measuringWidth()
        .onPreferenceChange(WidthPreferenceKey.self) { gridWidth = $0 }
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
