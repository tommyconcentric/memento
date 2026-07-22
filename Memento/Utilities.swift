import SwiftUI
import UIKit

// MARK: - String helpers

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First letters of the first two words, e.g. "Sofia Marques" → "SM".
    var personInitials: String {
        let parts = split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Date helpers

extension Date {
    /// The sentinel year contact import stores when the source birthday has
    /// no year (1904 is a leap year, so Feb 29 still constructs). Displays
    /// must hide it — the user never entered it.
    static let placeholderYear = 1904

    /// Placeholder years are Gregorian by definition; going through
    /// `Calendar.current` would mis-detect (and mis-construct) them on
    /// devices using the Buddhist or Japanese calendar, where "year 1904"
    /// is a different era entirely.
    static let gregorian = Calendar(identifier: .gregorian)

    var hasPlaceholderYear: Bool {
        Self.gregorian.component(.year, from: self) == Self.placeholderYear
    }

    /// The next occurrence of this date's month/day, today included.
    /// Feb 29 anniversaries have no exact match in non-leap years, so they
    /// fall back to Feb 28 that year rather than skipping to the next
    /// leap year.
    static func nextOccurrence(of date: Date) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        let todayYear = calendar.component(.year, from: today)

        func occurrence(inYear year: Int) -> Date? {
            var comps = DateComponents(year: year, month: month, day: day)
            if month == 2, day == 29,
               let feb1 = calendar.date(from: DateComponents(year: year, month: 2, day: 1)),
               calendar.range(of: .day, in: .month, for: feb1)?.count != 29 {
                comps.day = 28
            }
            return calendar.date(from: comps)
        }

        guard let thisYear = occurrence(inYear: todayYear) else { return nil }
        let next = thisYear >= today ? thisYear : (occurrence(inYear: todayYear + 1) ?? thisYear)
        return calendar.startOfDay(for: next)
    }

    /// Days from today until the next occurrence of this date's month/day.
    /// Returns 0 when the occurrence is today.
    static func daysUntilNextOccurrence(of date: Date) -> Int? {
        guard let next = nextOccurrence(of: date) else { return nil }
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.dateComponents([.day], from: today, to: next).day
    }
}

// MARK: - App-wide date format (Settings → Dates)

/// The user's chosen rendering for every date the app *displays*. Wire
/// formats (profile cards' fixed POSIX parse format) and system input
/// controls (DatePickers) are deliberately untouched.
enum AppDateFormat: String, CaseIterable, Identifiable {
    case system, dayMonthYear, monthDayYear, iso8601, dayMonthName, monthNameDay

    static let storageKey = "appDateFormat"

    static var current: AppDateFormat {
        AppDateFormat(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    var id: String { rawValue }

    /// Shown in the Settings picker: each option demonstrates itself with
    /// today's date.
    var label: String {
        if let pattern = fullPattern {
            return Self.cachedFormatter(pattern).string(from: .now)
        }
        return "System — \(Date.now.formatted(date: .abbreviated, time: .omitted))"
    }

    /// Explicit patterns; nil means "follow the device's region settings".
    var fullPattern: String? {
        switch self {
        case .system: return nil
        case .dayMonthYear: return "dd/MM/yyyy"
        case .monthDayYear: return "MM/dd/yyyy"
        case .iso8601: return "yyyy-MM-dd"
        case .dayMonthName: return "d MMM yyyy"
        case .monthNameDay: return "MMM d, yyyy"
        }
    }

    /// The year-less variant, for placeholder-year birthdays.
    var monthDayPattern: String? {
        switch self {
        case .system: return nil
        case .dayMonthYear: return "dd/MM"
        case .monthDayYear: return "MM/dd"
        case .iso8601: return "MM-dd"
        case .dayMonthName: return "d MMM"
        case .monthNameDay: return "MMM d"
        }
    }

    private static var formatterCache: [String: DateFormatter] = [:]
    static func cachedFormatter(_ pattern: String) -> DateFormatter {
        if let cached = formatterCache[pattern] { return cached }
        let formatter = DateFormatter()
        if pattern == Self.iso8601.fullPattern || pattern == Self.iso8601.monthDayPattern {
            // ISO 8601 fixes its digits as well as its calendar — pin
            // POSIX so locales with native numbering still emit ISO.
            formatter.locale = Locale(identifier: "en_US_POSIX")
        }
        // The explicit patterns are Gregorian by definition: left on the
        // device calendar, `yyyy` renders era years on Buddhist- or
        // Japanese-calendar devices (1990 → 2533 BE) and "ISO 8601"
        // stops being ISO. Only the "System" option follows the device,
        // and it never reaches this cache.
        formatter.calendar = Date.gregorian
        formatter.dateFormat = pattern
        formatterCache[pattern] = formatter
        return formatter
    }
}

extension Date {
    /// How verbose the *system* rendering should be when no explicit
    /// format is chosen; an explicit format always wins.
    enum AppFormatFallback { case abbreviated, long, complete }

    func appFormatted(_ fallback: AppFormatFallback = .abbreviated) -> String {
        if let pattern = AppDateFormat.current.fullPattern {
            return AppDateFormat.cachedFormatter(pattern).string(from: self)
        }
        switch fallback {
        case .abbreviated: return formatted(date: .abbreviated, time: .omitted)
        case .long: return formatted(date: .long, time: .omitted)
        case .complete: return formatted(date: .complete, time: .omitted)
        }
    }

    /// Month + day only — placeholder-year birthdays must never show the
    /// sentinel year.
    func appFormattedMonthDay() -> String {
        if let pattern = AppDateFormat.current.monthDayPattern {
            return AppDateFormat.cachedFormatter(pattern).string(from: self)
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Image compression

extension UIImage {
    /// Scales the image down (if needed) and returns JPEG data,
    /// keeping the on-device database small.
    func compressedData(maxDimension: CGFloat = 1400, quality: CGFloat = 0.8) -> Data? {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else {
            return jpegData(compressionQuality: quality)
        }
        let scale = maxDimension / largestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: - Avatar

/// Decoded-avatar cache: SwiftUI recreates rows constantly while
/// scrolling, and re-decoding a ~200 KB JPEG per row per frame is what
/// makes a several-hundred-person list stutter. Keyed by the photo Data
/// (NSData hashing is far cheaper than a decode); capped so photo-heavy
/// stores don't balloon memory.
private let avatarImageCache: NSCache<NSData, UIImage> = {
    let cache = NSCache<NSData, UIImage>()
    cache.countLimit = 300
    return cache
}()

/// Circular profile photo, or gradient initials when no photo is set.
struct AvatarView: View {
    let data: Data?
    let name: String
    var size: CGFloat = 44
    var desaturated: Bool = false
    /// Business contacts draw from the boardroom palette so each
    /// workspace's initials circles speak its own register.
    var business: Bool = false

    private func decodedImage(_ data: Data) -> UIImage? {
        let key = data as NSData
        if let cached = avatarImageCache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        avatarImageCache.setObject(image, forKey: key)
        return image
    }

    var body: some View {
        Group {
            if let data, let uiImage = decodedImage(data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [fallbackColor, fallbackColor.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(name.personInitials.isEmpty ? "?" : name.personInitials)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .saturation(desaturated ? 0 : 1)
        .opacity(desaturated ? 0.85 : 1)
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// Stable color derived from the name, so each person keeps their color.
    /// Personal circles use the warm holiday tones; business circles a set
    /// of muted boardroom tones. Neither palette contains blues or slate
    /// grays: selection paints rows in aegean (personal) or graphite
    /// (business), and an initials circle in a near-hue vanished into the
    /// selected row's own background.
    private var fallbackColor: Color {
        let palette: [Color] = business
            ? [
                Color(red: 0.18, green: 0.47, blue: 0.44),   // boardroom teal
                Color(red: 0.55, green: 0.27, blue: 0.30),   // oxblood
                Color(red: 0.58, green: 0.45, blue: 0.20),   // bronze
                Color(red: 0.44, green: 0.34, blue: 0.52),   // plum
                Color(red: 0.38, green: 0.44, blue: 0.31)    // moss
            ]
            : [
                Theme.bougainvillea, Theme.olive, Theme.terracotta,
                Theme.gold, Theme.bark
            ]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

// MARK: - Quick-info row

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Card style

/// The workspace whose surfaces `.mementoCard()` draws. Personal is the
/// default so standalone surfaces (settings, calendar, import, lock
/// screen — all on the personal whitewash) keep today's look; workspace-
/// themed roots override it once so business screens get slate cards and
/// a graphite hairline instead of Personal navy and aegean, without any
/// call-site changes.
private struct CardWorkspaceKey: EnvironmentKey {
    static let defaultValue = Workspace.personal
}

extension EnvironmentValues {
    var cardWorkspace: Workspace {
        get { self[CardWorkspaceKey.self] }
        set { self[CardWorkspaceKey.self] = newValue }
    }
}

/// The shared surface treatment: continuous corners, hairline border,
/// soft shadow. Keeps every card in the app consistent — tinted by the
/// `cardWorkspace` environment so each workspace's cards match its
/// background.
struct MementoCard: ViewModifier {
    var padding: CGFloat = 16
    @Environment(\.cardWorkspace) private var workspace

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(workspace.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(workspace.accent.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

extension View {
    func mementoCard(padding: CGFloat = 16) -> some View {
        modifier(MementoCard(padding: padding))
    }
}

// MARK: - Pill tab picker

/// Editorial underline tabs with a sliding indicator — serif labels,
/// hairline baseline.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var accent: Color = Theme.aegean
    var fontDesign: Font.Design = .serif
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = value
                    }
                } label: {
                    VStack(spacing: 9) {
                        Text(label)
                            .font(.system(.subheadline, design: fontDesign))
                            .fontWeight(selection == value ? .semibold : .regular)
                            .foregroundStyle(selection == value ? accent : Color.secondary)
                        ZStack {
                            if selection == value {
                                Rectangle()
                                    .fill(accent)
                                    .matchedGeometryEffect(id: "underline", in: indicator)
                            }
                        }
                        .frame(height: 2)
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(0.15))
                .frame(height: 1)
        }
    }
}
