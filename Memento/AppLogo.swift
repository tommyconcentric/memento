import SwiftUI

/// A recolorable variant of the app icon/logo. Cases mirror the alternate
/// icon asset sets in Assets.xcassets 1:1 — `iconAssetName` is exactly the
/// `.appiconset` folder name, so `UIApplication.setAlternateIconName` can use
/// it directly. Colors here match `generate_icons.swift`'s renders so the
/// in-app logo and the Home Screen icon never disagree.
enum LogoColorScheme: String, CaseIterable, Identifiable {
    case `default`, red, purple, orange, pink, green, navy, monochrome

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .red: return "Red"
        case .purple: return "Purple"
        case .orange: return "Orange"
        case .pink: return "Pink"
        case .green: return "Green"
        case .navy: return "Navy Blue"
        case .monochrome: return "Monochrome"
        }
    }

    /// Exact `.appiconset` folder name in Assets.xcassets; nil restores the
    /// app's primary icon.
    var iconAssetName: String? {
        switch self {
        case .default: return nil
        case .red: return "AppIcon-Red"
        case .purple: return "AppIcon-Purple"
        case .orange: return "AppIcon-Orange"
        case .pink: return "AppIcon-Pink"
        case .green: return "AppIcon-Green"
        case .navy: return "AppIcon-Navy"
        case .monochrome: return "AppIcon-Monochrome"
        }
    }

    var bg1: Color {
        switch self {
        case .default: return Color(red: 0.09, green: 0.34, blue: 0.49)
        case .red: return Color(red: 0.35, green: 0.07, blue: 0.09)
        case .purple: return Color(red: 0.19, green: 0.10, blue: 0.27)
        case .orange: return Color(red: 0.35, green: 0.16, blue: 0.05)
        case .pink: return Color(red: 0.36, green: 0.10, blue: 0.28)
        case .green: return Color(red: 0.12, green: 0.19, blue: 0.09)
        case .navy: return Color(red: 0.02, green: 0.05, blue: 0.12)
        case .monochrome: return Color(red: 0.14, green: 0.14, blue: 0.15)
        }
    }

    var bg2: Color {
        switch self {
        case .default: return Theme.sky
        case .red: return Color(red: 0.80, green: 0.20, blue: 0.18)
        case .purple: return Color(red: 0.55, green: 0.35, blue: 0.72)
        case .orange: return Color(red: 0.85, green: 0.45, blue: 0.15)
        case .pink: return Theme.bougainvillea
        case .green: return Color(red: 0.35, green: 0.62, blue: 0.28)
        case .navy: return Color(red: 0.09, green: 0.16, blue: 0.30)
        case .monochrome: return Color(red: 0.55, green: 0.55, blue: 0.57)
        }
    }

    var crown: Color {
        switch self {
        case .monochrome: return Color(white: 0.85)
        default: return Theme.sunshine
        }
    }
}

/// The Memento mark: a small tree whose canopy is three connected
/// people-nodes — family tree meets relationship graph. Drawn in code so
/// it stays crisp at any size; the 1024px app icon uses the same geometry.
struct LogoMark: View {
    var size: CGFloat = 40
    var colorScheme: LogoColorScheme = .default

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 1024
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Squircle background: deep sea into Santorini sky (or the chosen tint).
            let bg = Path(roundedRect: CGRect(origin: .zero, size: canvasSize),
                          cornerRadius: 232 * s, style: .continuous)
            context.fill(bg, with: .linearGradient(
                Gradient(colors: [colorScheme.bg1, colorScheme.bg2]),
                startPoint: .zero,
                endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
            ))

            var style = StrokeStyle(lineWidth: 54 * s, lineCap: .round)

            var trunk = Path()
            trunk.move(to: pt(512, 742))
            trunk.addLine(to: pt(512, 470))
            context.stroke(trunk, with: .color(.white), style: style)

            style.lineWidth = 46 * s
            var left = Path()
            left.move(to: pt(512, 470))
            left.addQuadCurve(to: pt(372, 336), control: pt(512, 372))
            var right = Path()
            right.move(to: pt(512, 470))
            right.addQuadCurve(to: pt(652, 336), control: pt(512, 372))
            var stem = Path()
            stem.move(to: pt(512, 470))
            stem.addLine(to: pt(512, 330))
            context.stroke(left, with: .color(.white), style: style)
            context.stroke(right, with: .color(.white), style: style)
            context.stroke(stem, with: .color(.white), style: style)

            style.lineWidth = 36 * s
            var rootL = Path()
            rootL.move(to: pt(512, 742))
            rootL.addQuadCurve(to: pt(430, 804), control: pt(498, 788))
            var rootR = Path()
            rootR.move(to: pt(512, 742))
            rootR.addQuadCurve(to: pt(594, 804), control: pt(526, 788))
            context.stroke(rootL, with: .color(.white.opacity(0.85)), style: style)
            context.stroke(rootR, with: .color(.white.opacity(0.85)), style: style)

            // People-nodes; the crown one carries the island sun.
            func node(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
                let rect = CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
            node(352, 314, 64, .white)
            node(672, 314, 64, .white)
            node(512, 262, 72, colorScheme.crown)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Memento")
    }
}

/// Logo + serif wordmark lockup.
struct LogoWordmark: View {
    var colorScheme: LogoColorScheme = .default

    var body: some View {
        HStack(spacing: 10) {
            LogoMark(size: 32, colorScheme: colorScheme)
            Text("Memento")
                .font(.system(size: 24, design: .serif))
                .fontWeight(.semibold)
        }
    }
}
