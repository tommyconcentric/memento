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

    var hasPlaceholderYear: Bool {
        Calendar.current.component(.year, from: self) == Self.placeholderYear
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
    private var fallbackColor: Color {
        let palette: [Color] = [
            Theme.aegean, Theme.sky, Theme.bougainvillea,
            Theme.olive, Theme.terracotta, Theme.gold
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

/// The shared surface treatment: continuous corners, hairline border,
/// soft shadow. Keeps every card in the app consistent.
struct MementoCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.aegean.opacity(0.14), lineWidth: 1)
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
