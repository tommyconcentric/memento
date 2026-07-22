import SwiftUI
import UIKit

/// Crop a picked photo into the profile circle. The image pans and pinches
/// under a fixed circle; everything outside it is darkened so the
/// preview shows exactly what the avatar will look like.
struct PhotoCropperView: View {
    let image: UIImage
    var onCrop: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - 72
            let base = baseSize(for: side)

            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .frame(width: base.width * zoom, height: base.height * zoom)
                    .offset(clamped(offset, base: base, side: side))

                // Live preview: darken everything outside the circle.
                // This layer must NOT ignore the safe area: the sheet's
                // asymmetric insets on iPhone (0 top, home-indicator bottom)
                // would re-center the mask — and its punched-out circle — in
                // the expanded bounds, sliding the bright hole below the
                // stroked ring and the region crop() captures. Laid out in
                // the same geo bounds as the ring, the two stay concentric;
                // the uncovered safe-area strips stay solid black via the
                // outer .background(Color.black).
                let frameShape = Circle()
                Color.black.opacity(0.55)
                    .mask {
                        Rectangle()
                            .overlay(
                                frameShape
                                    .frame(width: side, height: side)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)

                frameShape
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)

                VStack {
                    HStack {
                        Button("Cancel") { dismiss() }
                        Spacer()
                        Text("Drag to position \u{00B7} double-tap resets")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Button("Choose") {
                            crop(side: side, base: base)
                            dismiss()
                        }
                        .fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    Spacer()
                    // A click-reachable zoom control: pinch works on touch
                    // screens and trackpads, but a mouse on the Mac has no
                    // pinch input at all — without this slider, Mac users
                    // could never zoom past the minimum fit.
                    HStack(spacing: 12) {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: zoomBinding(base: base, side: side), in: 1...5)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                    .frame(maxWidth: 420)
                }
            }
            // The zoomed image's rigid frame would otherwise inflate the
            // ZStack past the screen (a ZStack reports the union of its
            // children, and GeometryReader pins content top-leading), which
            // dragged the crop circle and toolbar off-center. Pinning the
            // stack to the view's size keeps everything screen-centered at
            // any zoom; clipping hides the overflowing image edges.
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                dragGesture(base: base, side: side)
                    .simultaneously(with: zoomGesture(base: base, side: side))
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    zoom = 1
                    steadyZoom = 1
                    offset = .zero
                    steadyOffset = .zero
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - Geometry

    /// The image scaled so its shorter edge exactly fills the circle.
    private func baseSize(for side: CGFloat) -> CGSize {
        let scale = side / max(1, min(image.size.width, image.size.height))
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func clamped(_ proposed: CGSize, base: CGSize, side: CGFloat) -> CGSize {
        let maxX = max(0, (base.width * zoom - side) / 2)
        let maxY = max(0, (base.height * zoom - side) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    /// Slider writes mirror the pinch gesture's behavior, keeping the two
    /// inputs interchangeable: update both live and steady zoom, and
    /// re-clamp the offset so the image never drifts off the circle.
    private func zoomBinding(base: CGSize, side: CGFloat) -> Binding<CGFloat> {
        Binding(
            get: { zoom },
            set: { newValue in
                zoom = min(5, max(1, newValue))
                steadyZoom = zoom
                steadyOffset = clamped(steadyOffset, base: base, side: side)
                offset = steadyOffset
            }
        )
    }

    // MARK: - Gestures

    private func dragGesture(base: CGSize, side: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let raw = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
                let bound = clamped(raw, base: base, side: side)
                // Rubber-band past the edge instead of hard-stopping.
                offset = CGSize(
                    width: bound.width + (raw.width - bound.width) * 0.35,
                    height: bound.height + (raw.height - bound.height) * 0.35
                )
            }
            .onEnded { value in
                let raw = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
                steadyOffset = clamped(raw, base: base, side: side)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    offset = steadyOffset
                }
            }
    }

    private func zoomGesture(base: CGSize, side: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(5, max(1, steadyZoom * value))
            }
            .onEnded { _ in
                steadyZoom = zoom
                steadyOffset = clamped(steadyOffset, base: base, side: side)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    offset = steadyOffset
                }
            }
    }

    // MARK: - Render the crop

    private func crop(side: CGFloat, base: CGSize) {
        let clampedOffset = clamped(offset, base: base, side: side)
        let pointsPerPixel = (base.width / image.size.width) * zoom
        let visibleSide = side / pointsPerPixel
        let centerX = image.size.width / 2 - clampedOffset.width / pointsPerPixel
        let centerY = image.size.height / 2 - clampedOffset.height / pointsPerPixel
        let originX = centerX - visibleSide / 2
        let originY = centerY - visibleSide / 2

        let output: CGFloat = 600
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(
            size: CGSize(width: output, height: output), format: format
        ).image { _ in
            let k = output / visibleSide
            image.draw(in: CGRect(
                x: -originX * k, y: -originY * k,
                width: image.size.width * k, height: image.size.height * k
            ))
        }
        if let data = rendered.jpegData(compressionQuality: 0.82) {
            onCrop(data)
        }
    }
}
