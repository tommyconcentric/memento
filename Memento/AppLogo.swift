import SwiftUI

/// The Memento mark: a small tree whose canopy is three connected
/// people-nodes. Family tree meets relationship graph. Drawn in code so
/// it stays crisp at any size; the 1024px app icon uses the same geometry.
struct LogoMark: View {
    var size: CGFloat = 40

    // The one and only palette. The recolor feature (alternate icons +
    // in-app scheme picker) was removed; the logo is always the default.
    private let bg1 = Color(red: 0.09, green: 0.34, blue: 0.49)
    private let bg2 = Theme.sky
    private let crown = Theme.sunshine

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 1024
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Squircle background: deep sea into Santorini sky (or the chosen tint).
            let bg = Path(roundedRect: CGRect(origin: .zero, size: canvasSize),
                          cornerRadius: 232 * s, style: .continuous)
            context.fill(bg, with: .linearGradient(
                Gradient(colors: [bg1, bg2]),
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
            node(512, 262, 72, crown)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Memento")
    }
}

/// Logo + serif wordmark lockup.
struct LogoWordmark: View {
    var body: some View {
        HStack(spacing: 10) {
            LogoMark(size: 32)
            Text("Memento")
                .font(.system(size: 24, design: .serif))
                .fontWeight(.semibold)
        }
    }
}
