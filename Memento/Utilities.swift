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
    /// Days from today until the next occurrence of this date's month/day.
    /// Returns 0 when the occurrence is today.
    static func daysUntilNextOccurrence(of date: Date) -> Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let next = calendar.nextDate(
            after: today.addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTime
        ) else { return nil }
        return calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: next)).day
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

/// Circular profile photo, or gradient initials when no photo is set.
struct AvatarView: View {
    let data: Data?
    let name: String
    var size: CGFloat = 44
    var desaturated: Bool = false

    var body: some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
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
                            .font(.system(.subheadline, design: .serif))
                            .fontWeight(selection == value ? .semibold : .regular)
                            .foregroundStyle(selection == value ? Theme.aegean : Color.secondary)
                        ZStack {
                            if selection == value {
                                Rectangle()
                                    .fill(Theme.aegean)
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
                .fill(Theme.aegean.opacity(0.15))
                .frame(height: 1)
        }
    }
}
