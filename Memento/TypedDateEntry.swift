import SwiftUI

// MARK: - Parsing typed dates

/// Turns what a user types into a date: "12/03/1991", "12/3", "12.3.91",
/// "Mar 12", "12 Mar 1991". It reads the components in the order of the
/// app's chosen date format. A date without a year is valid: birthdays keep
/// only the day and month via the placeholder year.
enum TypedDateParser {

    struct Parsed {
        let date: Date
        let isYearless: Bool
    }

    /// What a missing year should become.
    enum YearlessStyle {
        case placeholderYear   // birthdays: "no year recorded"
        case currentYear       // important dates: assume this year
    }

    private enum Component { case day, month, year }

    static func parse(
        _ text: String,
        format: AppDateFormat = .current,
        yearless: YearlessStyle = .placeholderYear
    ) -> Parsed? {
        let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !tokens.isEmpty, tokens.count <= 3 else { return nil }

        let calendar = parsingCalendar(for: format)

        var day: Int?
        var month: Int?
        var year: Int?

        let words = tokens.filter { $0.contains(where: \.isLetter) }
        let numbers = tokens.filter { !$0.contains(where: \.isLetter) }.compactMap { Int($0) }
        guard words.count <= 1, numbers.count + words.count == tokens.count else { return nil }

        if let word = words.first {
            // A written month ("Mar", "March", "mars") in the user's
            // locale or English.
            guard let named = monthNumber(for: word, calendar: calendar) else { return nil }
            month = named
            switch numbers.count {
            case 1:
                day = numbers[0]
            case 2:
                // The year trails a written month in every format that shows
                // one ("Mar 12, 1991" / "12 Mar 1991"), unless the first
                // number can't be a day ("1991 Mar 12").
                if numbers[0] > 31 {
                    (year, day) = (numbers[0], numbers[1])
                } else {
                    (day, year) = (numbers[0], numbers[1])
                }
            default:
                return nil
            }
        } else {
            let order = componentOrder(for: format)
            switch numbers.count {
            case 2:
                // Day and month in the format's order, year omitted.
                let dayPosition = order.firstIndex(of: .day) ?? 0
                let monthPosition = order.firstIndex(of: .month) ?? 1
                let dayFirst = dayPosition < monthPosition
                day = dayFirst ? numbers[0] : numbers[1]
                month = dayFirst ? numbers[1] : numbers[0]
            case 3:
                for (index, component) in order.enumerated() {
                    switch component {
                    case .day: day = numbers[index]
                    case .month: month = numbers[index]
                    case .year: year = numbers[index]
                    }
                }
            default:
                return nil
            }
        }

        guard let day, let month, (1...12).contains(month) else { return nil }

        let currentYear = calendar.component(.year, from: .now)
        let isYearless = year == nil
        var resolvedYear: Int
        if var typed = year {
            // "91" means 1991, "05" means 2005. Expand into the century
            // nearest today *in the parsing calendar*, so Buddhist (2569)
            // and Hebrew (5786) system calendars expand correctly too.
            if typed < 100 {
                let century = (currentYear / 100) * 100
                typed += century
                if typed > currentYear + 10 { typed -= 100 }
            }
            guard (1900...currentYear + 10).contains(typed) else { return nil }
            resolvedYear = typed
        } else {
            switch yearless {
            case .placeholderYear: resolvedYear = Date.placeholderYear
            case .currentYear: resolvedYear = currentYear
            }
        }

        // Placeholder years are Gregorian by definition (see Date.gregorian).
        let buildCalendar = isYearless && yearless == .placeholderYear ? Date.gregorian : calendar
        var components = DateComponents(year: resolvedYear, month: month, day: day)
        guard let first = buildCalendar.date(from: DateComponents(year: resolvedYear, month: month)),
              let daysInMonth = buildCalendar.range(of: .day, in: .month, for: first)?.count,
              (1...daysInMonth).contains(day) else { return nil }
        components.hour = 0
        guard let date = buildCalendar.date(from: components) else { return nil }
        return Parsed(date: date, isYearless: isYearless)
    }

    /// The order the user types components in, which is the same order the
    /// format displays them.
    private static func componentOrder(for format: AppDateFormat) -> [Component] {
        switch format {
        case .dayMonthYear, .dayMonthName: return [.day, .month, .year]
        case .monthDayYear, .monthNameDay: return [.month, .day, .year]
        case .iso8601: return [.year, .month, .day]
        case .system:
            // Follow the device's convention: does the locale write the day
            // or the month first?
            let template = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0,
                                                    locale: .current) ?? "M/d/y"
            let positions: [(Component, String.Index?)] = [
                (.day, template.firstIndex(of: "d")),
                (.month, template.firstIndex(of: "M")),
                (.year, template.firstIndex(of: "y"))
            ]
            return positions
                .compactMap { component, index in index.map { (component, $0) } }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
        }
    }

    /// The explicit formats are pinned Gregorian (matching their display
    /// formatters); System follows the device, with the same sub-1900-era
    /// defense as AppDatePicker.
    private static func parsingCalendar(for format: AppDateFormat) -> Calendar {
        guard format == .system else { return Date.gregorian }
        let current = Calendar.current
        if current.component(.year, from: .now) >= 1900 { return current }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = current.locale
        gregorian.timeZone = current.timeZone
        return gregorian
    }

    private static func monthNumber(for word: String, calendar: Calendar) -> Int? {
        let target = word.lowercased()
        guard target.count >= 3 else { return nil }
        var symbolSets = [calendar.monthSymbols, calendar.shortMonthSymbols]
        // English month names always work, whatever the device language.
        let english = Date.gregorian
        symbolSets.append(contentsOf: [english.monthSymbols, english.shortMonthSymbols])
        let posix = DateFormatter()
        posix.locale = Locale(identifier: "en_US_POSIX")
        symbolSets.append(posix.monthSymbols)
        for symbols in symbolSets {
            if let index = symbols.firstIndex(where: {
                let name = $0.lowercased()
                return name == target || name.hasPrefix(target)
            }) {
                return index + 1
            }
        }
        return nil
    }
}

// MARK: - Editable date text

/// The date readout that is also a text field: shows the date in the app's
/// format, lets the user type one directly (with or without a year) and
/// validates as they go. Every keystroke that parses commits immediately, so
/// the date is never lost to a Save (or a sheet dismissal) that arrives while
/// the field still has focus; blur and ⏎ just normalize the text back to the
/// display form. An external change, such as a tap in the day grid, always
/// wins and resets whatever was mid-typing: the calendar and the text must
/// never disagree about the date they both show.
struct DateEntryText: View {
    @Binding var date: Date
    var accent: Color = Theme.aegean
    /// Birthdays keep a typed day/month as "no year recorded"; important
    /// dates assume the current year instead.
    var yearlessStyle: TypedDateParser.YearlessStyle = .placeholderYear

    @State private var text = ""
    @State private var isInvalid = false
    // Distinguishes our own live commit from an external date change (the
    // calendar), which must reset the text even mid-typing.
    @State private var committingOwnEdit = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .multilineTextAlignment(.trailing)
            .keyboardType(usesWrittenMonth ? .default : .numbersAndPunctuation)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .fontWeight(.medium)
            .foregroundStyle(isInvalid ? Theme.terracotta : accent)
            .frame(maxWidth: 170)
            .onAppear { text = displayText }
            .onChange(of: date) {
                if committingOwnEdit {
                    committingOwnEdit = false
                } else {
                    text = displayText
                    isInvalid = false
                }
            }
            .onChange(of: text) {
                guard focused else { return }
                if let parsed = TypedDateParser.parse(text, yearless: yearlessStyle) {
                    isInvalid = false
                    // Live-commit only full dates: committing a year-less
                    // parse mid-typing would flip a birthday to the
                    // placeholder year while "12/3" is still on its way to
                    // "12/3/1991". The editor swaps views on that, which
                    // kills the keyboard. Year-less entries commit on blur.
                    if !parsed.isYearless, parsed.date != date {
                        committingOwnEdit = true
                        date = parsed.date
                    }
                } else {
                    isInvalid = !text.trimmed.isEmpty
                }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onSubmit(commit)
            .accessibilityLabel("Date, type to change")
    }

    private var displayText: String {
        date.hasPlaceholderYear ? date.appFormattedMonthDay() : date.appFormatted()
    }

    private var usesWrittenMonth: Bool {
        switch AppDateFormat.current {
        case .dayMonthName, .monthNameDay, .system: return true
        default: return false
        }
    }

    /// "DD/MM/YYYY" for the numeric formats. The pattern doubles as the
    /// how-to-type hint.
    private var placeholder: String {
        AppDateFormat.current.fullPattern?.uppercased() ?? "Date"
    }

    /// Blur/⏎: full dates are already committed keystroke-by-keystroke; this
    /// commits a pending year-less entry, then settles the text into the
    /// canonical display form (reverting leftover invalid text).
    private func commit() {
        if let parsed = TypedDateParser.parse(text, yearless: yearlessStyle), parsed.date != date {
            committingOwnEdit = true
            date = parsed.date
        }
        text = displayText
        isInvalid = false
    }
}
