import SwiftUI
import AppKit

// Regenerates the alternate app icon PNGs (see AboutView's "App Icon Color"
// picker). Run from the repo root: `swift Scripts/generate_icons.swift`,
// then copy each output into Memento/Assets.xcassets/AppIcon-<Name>.appiconset/
// replacing the existing PNG (filenames already match). To add a color,
// add a Variant below AND a matching case in AppLogo.swift's LogoColorScheme
// (same bg1/bg2/crown values) plus a new .appiconset folder + Contents.json.
//
// Re-draws the Memento tree-of-people mark (same geometry as AppLogo.swift's
// LogoMark) as a full-bleed square with no transparency, per Apple's app
// icon requirements — the OS applies its own corner mask at display time.
struct IconArt: View {
    var bg1: Color
    var bg2: Color
    var crown: Color

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 1024
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .linearGradient(
                    Gradient(colors: [bg1, bg2]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                )
            )

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

            func node(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
                let rect = CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
            node(352, 314, 64, .white)
            node(672, 314, 64, .white)
            node(512, 262, 72, crown)
        }
        .frame(width: 1024, height: 1024)
    }
}

struct Variant {
    let name: String
    let bg1: Color
    let bg2: Color
    let crown: Color
}

let sunshine = Color(red: 0.949, green: 0.757, blue: 0.306)
let deepAegean = Color(red: 0.09, green: 0.34, blue: 0.49)

let variants: [Variant] = [
    Variant(name: "Red", bg1: Color(red: 0.35, green: 0.07, blue: 0.09), bg2: Color(red: 0.80, green: 0.20, blue: 0.18), crown: sunshine),
    Variant(name: "Purple", bg1: Color(red: 0.19, green: 0.10, blue: 0.27), bg2: Color(red: 0.55, green: 0.35, blue: 0.72), crown: sunshine),
    Variant(name: "Orange", bg1: Color(red: 0.35, green: 0.16, blue: 0.05), bg2: Color(red: 0.85, green: 0.45, blue: 0.15), crown: sunshine),
    Variant(name: "Yellow", bg1: Color(red: 0.35, green: 0.27, blue: 0.05), bg2: sunshine, crown: deepAegean),
    Variant(name: "Green", bg1: Color(red: 0.12, green: 0.19, blue: 0.09), bg2: Color(red: 0.35, green: 0.62, blue: 0.28), crown: sunshine),
    Variant(name: "Navy", bg1: Color(red: 0.02, green: 0.05, blue: 0.12), bg2: Color(red: 0.09, green: 0.16, blue: 0.30), crown: sunshine),
    Variant(name: "Monochrome", bg1: Color(red: 0.14, green: 0.14, blue: 0.15), bg2: Color(red: 0.55, green: 0.55, blue: 0.57), crown: Color(white: 0.85)),
]

let outDir = FileManager.default.currentDirectoryPath + "/generated-icons"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    for variant in variants {
        let view = IconArt(bg1: variant.bg1, bg2: variant.bg2, crown: variant.crown)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else {
            print("FAILED: \(variant.name)")
            continue
        }
        // Flatten onto an explicitly alpha-free RGB context — Apple's app
        // icon validator rejects any icon with an alpha channel, even if
        // fully opaque, and ImageRenderer always produces one otherwise.
        let width = cgImage.width, height = cgImage.height
        guard let flatContext = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            print("FAILED context: \(variant.name)")
            continue
        }
        flatContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let flatImage = flatContext.makeImage() else {
            print("FAILED flatten: \(variant.name)")
            continue
        }
        let rep = NSBitmapImageRep(cgImage: flatImage)
        guard let data = rep.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
            print("FAILED encode: \(variant.name)")
            continue
        }
        let path = "\(outDir)/AppIcon-\(variant.name)-1024.png"
        try! data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(cgImage.width)x\(cgImage.height))")
    }
}
