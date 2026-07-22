import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - FileDocument wrapper (for .fileExporter)

/// Wraps rendered PDF bytes so SwiftUI's fileExporter can save them — the
/// exporter presents a save panel on the Mac and the Files sheet on iOS,
/// the one delivery path that behaves identically on both.
struct PDFExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Notes PDF export

/// Renders a person's notes timeline as a paginated A4 PDF, in the voice of
/// their workspace: business contacts get a crisp sans-serif report (white
/// pages, graphite and steel), personal people get a warm scrapbook (the
/// parchment background, serif type, polaroid-framed photos). One shared
/// composer paginates both; only the `Style` differs.
enum NotesPDFExporter {

    static func render(for person: Person) -> Data {
        let style = Style(business: person.isBusiness)
        let composer = Composer(style: style)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(person.name) — Notes",
            kCGPDFContextCreator as String: "Memento"
        ]
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: Composer.pageSize),
            format: format
        )
        let notes = person.sortedNotes
        return renderer.pdfData { context in
            composer.context = context
            composer.startPage()
            if person.isBusiness {
                composer.drawBusinessHeader(person, noteCount: notes.count)
            } else {
                composer.drawScrapbookHeader(person, notes: notes)
            }
            for (index, note) in notes.enumerated() {
                composer.drawNote(note)
                if index < notes.count - 1 {
                    composer.drawDivider()
                }
            }
        }
    }

    /// Suggested save name; the person's name may contain path separators.
    static func filename(for person: Person) -> String {
        let safeName = person.name.replacingOccurrences(of: "/", with: "-")
        return person.isBusiness ? "\(safeName) — Notes Report" : "\(safeName) — Scrapbook"
    }

    // MARK: - Style

    /// Fixed light-mode palettes (a PDF has no dark mode) matching the
    /// app's Theme hex values, plus each workspace's type voice.
    private struct Style {
        let business: Bool
        let pageBackground: UIColor
        let ink: UIColor
        let subInk: UIColor
        let accent: UIColor
        let rule: UIColor
        let warm: UIColor      // date lines in the scrapbook; unused ribbon in reports

        init(business: Bool) {
            self.business = business
            if business {
                pageBackground = .white
                ink = UIColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1)
                subInk = UIColor(red: 0.42, green: 0.46, blue: 0.52, alpha: 1)
                accent = UIColor(red: 0.239, green: 0.290, blue: 0.361, alpha: 1)   // graphite
                rule = UIColor(red: 0.475, green: 0.565, blue: 0.663, alpha: 0.45)  // steel
                warm = UIColor(red: 0.475, green: 0.565, blue: 0.663, alpha: 1)
            } else {
                pageBackground = UIColor(red: 0.980, green: 0.965, blue: 0.937, alpha: 1) // whitewash
                ink = UIColor(red: 0.18, green: 0.14, blue: 0.10, alpha: 1)
                subInk = UIColor(red: 0.47, green: 0.41, blue: 0.34, alpha: 1)
                accent = UIColor(red: 0.118, green: 0.431, blue: 0.624, alpha: 1)   // aegean
                rule = UIColor(red: 0.753, green: 0.541, blue: 0.176, alpha: 0.55)  // gold
                warm = UIColor(red: 0.788, green: 0.435, blue: 0.290, alpha: 1)     // terracotta
            }
        }

        /// Serif for the scrapbook, system sans for the report — the same
        /// split `Workspace.displayFontDesign` makes in the app.
        func font(_ size: CGFloat, _ weight: UIFont.Weight, italic: Bool = false) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            var descriptor = base.fontDescriptor
            if !business, let serif = descriptor.withDesign(.serif) {
                descriptor = serif
            }
            if italic {
                let traits = descriptor.symbolicTraits.union(.traitItalic)
                if let italicised = descriptor.withSymbolicTraits(traits) {
                    descriptor = italicised
                }
            }
            return UIFont(descriptor: descriptor, size: size)
        }
    }

    // MARK: - Composer (pagination + drawing)

    private final class Composer {
        static let pageSize = CGSize(width: 595.2, height: 841.8)   // A4
        private let margin: CGFloat = 54
        private var contentWidth: CGFloat { Self.pageSize.width - margin * 2 }
        private var bottomLimit: CGFloat { Self.pageSize.height - 64 }

        let style: Style
        var context: UIGraphicsPDFRendererContext!
        private var y: CGFloat = 0
        private var pageNumber = 0
        private var photoIndex = 0   // drives the scrapbook's alternating tilt

        init(style: Style) {
            self.style = style
        }

        // MARK: Pages

        func startPage() {
            context.beginPage()
            pageNumber += 1
            style.pageBackground.setFill()
            UIRectFill(CGRect(origin: .zero, size: Self.pageSize))
            drawFooter()
            y = margin
        }

        private func ensure(_ height: CGFloat) {
            if y + height > bottomLimit {
                startPage()
            }
        }

        private func drawFooter() {
            let footerY = Self.pageSize.height - 40
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: footerY))
            line.addLine(to: CGPoint(x: Self.pageSize.width - margin, y: footerY))
            line.lineWidth = 0.5
            style.rule.setStroke()
            line.stroke()

            let caption = style.font(8, .regular)
            let left = attributed(style.business ? "Prepared with Memento" : "Made with Memento",
                                  font: caption, color: style.subInk)
            left.draw(at: CGPoint(x: margin, y: footerY + 7))
            let right = attributed("Page \(pageNumber)", font: caption, color: style.subInk)
            let rightSize = right.size()
            right.draw(at: CGPoint(x: Self.pageSize.width - margin - rightSize.width, y: footerY + 7))
        }

        // MARK: Headers

        func drawBusinessHeader(_ person: Person, noteCount: Int) {
            // Masthead: wordmark left, report label right, both letterspaced.
            let mast = attributed("MEMENTO", font: style.font(10, .semibold), color: style.accent, kern: 3)
            mast.draw(at: CGPoint(x: margin, y: y))
            let label = attributed("CONTACT NOTES REPORT", font: style.font(8, .medium), color: style.warm, kern: 2)
            let labelSize = label.size()
            label.draw(at: CGPoint(x: Self.pageSize.width - margin - labelSize.width, y: y + 2))
            y += 22
            drawRule(weight: 1)
            y += 18

            drawParagraph(attributed(person.name, font: style.font(22, .bold), color: style.ink), spacingAfter: 4)
            let work = [person.jobTitle, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
            if !work.isEmpty {
                drawParagraph(attributed(work, font: style.font(11, .medium), color: style.accent), spacingAfter: 3)
            }
            let contact = [person.phoneNumber, person.email].filter { !$0.isEmpty }.joined(separator: "   ·   ")
            if !contact.isEmpty {
                drawParagraph(attributed(contact, font: style.font(9.5, .regular), color: style.subInk), spacingAfter: 3)
            }
            y += 8
            drawRule(weight: 0.5)
            y += 10
            let meta = "\(noteCount) \(noteCount == 1 ? "note" : "notes"), newest first · Exported \(Date.now.formatted(date: .abbreviated, time: .omitted))"
            drawParagraph(attributed(meta, font: style.font(8.5, .regular), color: style.subInk), spacingAfter: 22)
        }

        func drawScrapbookHeader(_ person: Person, notes: [NoteEntry]) {
            // Round portrait over a centred serif title — the framed-photo
            // look of the app's tree portraits, in print.
            let portraitSize: CGFloat = 68
            let portraitRect = CGRect(x: (Self.pageSize.width - portraitSize) / 2, y: y,
                                      width: portraitSize, height: portraitSize)
            drawCircularPortrait(person, in: portraitRect)
            y += portraitSize + 14

            drawParagraph(attributed(person.name, font: style.font(24, .semibold), color: style.ink,
                                     alignment: .center), spacingAfter: 4)
            drawParagraph(attributed("A scrapbook of notes & memories", font: style.font(11.5, .regular, italic: true),
                                     color: style.subInk, alignment: .center), spacingAfter: 6)
            if let newest = notes.first?.eventDate, let oldest = notes.last?.eventDate {
                let span = oldest.formatted(.dateTime.month(.abbreviated).year())
                    + " — " + newest.formatted(.dateTime.month(.abbreviated).year())
                let meta = "\(notes.count) \(notes.count == 1 ? "note" : "notes") · \(span)"
                drawParagraph(attributed(meta, font: style.font(9.5, .regular), color: style.subInk,
                                         alignment: .center), spacingAfter: 14)
            }
            drawDivider()
        }

        private func drawCircularPortrait(_ person: Person, in rect: CGRect) {
            let cg = context.cgContext
            cg.saveGState()
            UIBezierPath(ovalIn: rect).addClip()
            if let data = person.profilePhotoData, let image = UIImage(data: data) {
                drawAspectFill(image, in: rect)
            } else {
                style.accent.setFill()
                UIRectFill(rect)
                let initials = person.name.personInitials.isEmpty ? "?" : person.name.personInitials
                let text = attributed(initials, font: style.font(rect.height * 0.36, .semibold), color: .white)
                let size = text.size()
                text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            }
            cg.restoreGState()
            let ring = UIBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5))
            ring.lineWidth = 1.5
            UIColor(red: 0.753, green: 0.541, blue: 0.176, alpha: 0.8).setStroke()
            ring.stroke()
        }

        // MARK: Notes

        func drawNote(_ note: NoteEntry) {
            ensure(90)   // keep the date line and a couple of text lines together

            var dateLine: String
            if style.business {
                dateLine = note.eventDate.formatted(.dateTime.day().month(.abbreviated).year()).uppercased()
                if !note.location.isEmpty { dateLine += "   ·   \(note.location.uppercased())" }
                drawParagraph(attributed(dateLine, font: style.font(9, .semibold), color: style.accent, kern: 1),
                              spacingAfter: 5)
            } else {
                dateLine = note.eventDate.formatted(.dateTime.day().month(.wide).year())
                if !note.location.isEmpty { dateLine += " · \(note.location)" }
                drawParagraph(attributed(dateLine, font: style.font(10.5, .regular, italic: true), color: style.warm),
                              spacingAfter: 5)
            }

            if !note.title.isEmpty {
                drawParagraph(attributed(note.title, font: style.font(style.business ? 13 : 14, .semibold),
                                         color: style.ink), spacingAfter: 5)
            }
            if !note.text.isEmpty {
                drawParagraph(attributed(note.text, font: style.font(style.business ? 10.5 : 11.5, .regular),
                                         color: style.ink, lineSpacing: style.business ? 3 : 3.5),
                              spacingAfter: 8)
            }

            let photos = note.sortedPhotos.compactMap { photo in
                photo.imageData.flatMap(UIImage.init(data:)).map { ($0, photo.caption) }
            }
            if !photos.isEmpty {
                drawPhotoRows(photos)
            }
            y += 10
        }

        /// Up to three photos per row. Report style: clean rounded
        /// rectangles with a caption underneath. Scrapbook style: white
        /// polaroid frames with the caption on the mat, each tilted a
        /// hair off level — casual, but on a straight baseline.
        private func drawPhotoRows(_ photos: [(image: UIImage, caption: String)]) {
            let perRow = 3
            let gap: CGFloat = 10
            let cellWidth = (contentWidth - gap * CGFloat(perRow - 1)) / CGFloat(perRow)

            for start in stride(from: 0, to: photos.count, by: perRow) {
                let row = Array(photos[start..<min(start + perRow, photos.count)])
                let rowHeight = style.business
                    ? cellWidth * 0.72 + (row.contains { !$0.caption.isEmpty } ? 16 : 0)
                    : cellWidth * 0.78 + 26
                ensure(rowHeight + 8)
                for (column, photo) in row.enumerated() {
                    let cell = CGRect(x: margin + CGFloat(column) * (cellWidth + gap), y: y,
                                      width: cellWidth, height: rowHeight)
                    if style.business {
                        drawReportPhoto(photo.image, caption: photo.caption, in: cell)
                    } else {
                        drawPolaroid(photo.image, caption: photo.caption, in: cell)
                    }
                    photoIndex += 1
                }
                y += rowHeight + 10
            }
        }

        private func drawReportPhoto(_ image: UIImage, caption: String, in cell: CGRect) {
            let imageRect = CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: cell.width * 0.72)
            let cg = context.cgContext
            cg.saveGState()
            UIBezierPath(roundedRect: imageRect, cornerRadius: 6).addClip()
            drawAspectFill(image, in: imageRect)
            cg.restoreGState()
            if !caption.isEmpty {
                let text = attributed(caption, font: style.font(8, .regular), color: style.subInk)
                text.draw(in: CGRect(x: cell.minX, y: imageRect.maxY + 4, width: cell.width, height: 12))
            }
        }

        private func drawPolaroid(_ image: UIImage, caption: String, in cell: CGRect) {
            let cg = context.cgContext
            cg.saveGState()
            // Alternate a gentle tilt around the cell's centre.
            let tilts: [CGFloat] = [-1.4, 1.1, -0.7, 1.5, -1.0, 0.8]
            let angle = tilts[photoIndex % tilts.count] * .pi / 180
            cg.translateBy(x: cell.midX, y: cell.midY)
            cg.rotate(by: angle)
            cg.translateBy(x: -cell.midX, y: -cell.midY)

            let frame = cell.insetBy(dx: 2, dy: 2)
            cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 4,
                         color: UIColor.black.withAlphaComponent(0.18).cgColor)
            UIColor.white.setFill()
            UIBezierPath(rect: frame).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)

            let inset: CGFloat = 7
            let photoRect = CGRect(x: frame.minX + inset, y: frame.minY + inset,
                                   width: frame.width - inset * 2,
                                   height: frame.height - inset * 2 - 20)
            cg.saveGState()
            UIBezierPath(rect: photoRect).addClip()
            drawAspectFill(image, in: photoRect)
            cg.restoreGState()

            if !caption.isEmpty {
                let text = attributed(caption, font: style.font(8.5, .regular, italic: true),
                                      color: style.subInk, alignment: .center)
                text.draw(in: CGRect(x: frame.minX + 4, y: photoRect.maxY + 4,
                                     width: frame.width - 8, height: 14))
            }
            cg.restoreGState()
        }

        private func drawAspectFill(_ image: UIImage, in rect: CGRect) {
            let scale = max(rect.width / max(image.size.width, 1),
                            rect.height / max(image.size.height, 1))
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: rect.midX - drawSize.width / 2,
                                  y: rect.midY - drawSize.height / 2,
                                  width: drawSize.width, height: drawSize.height))
        }

        // MARK: Rules & ornaments

        private func drawRule(weight: CGFloat) {
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y))
            line.addLine(to: CGPoint(x: Self.pageSize.width - margin, y: y))
            line.lineWidth = weight
            (weight >= 1 ? UIColor(cgColor: style.accent.cgColor) : style.rule).setStroke()
            line.stroke()
        }

        /// Between-notes separator: a steel hairline in the report, three
        /// gold dots in the scrapbook.
        func drawDivider() {
            ensure(24)
            if style.business {
                y += 4
                drawRule(weight: 0.5)
                y += 14
            } else {
                let dotRadius: CGFloat = 1.8
                let spacing: CGFloat = 12
                let centerX = Self.pageSize.width / 2
                UIColor(red: 0.753, green: 0.541, blue: 0.176, alpha: 0.85).setFill()
                for offset in [-spacing, 0, spacing] {
                    let dot = CGRect(x: centerX + offset - dotRadius, y: y + 4 - dotRadius,
                                     width: dotRadius * 2, height: dotRadius * 2)
                    UIBezierPath(ovalIn: dot).fill()
                }
                y += 20
            }
        }

        // MARK: Text

        private func attributed(_ string: String, font: UIFont, color: UIColor, kern: CGFloat = 0,
                                lineSpacing: CGFloat = 0, alignment: NSTextAlignment = .natural) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing
            paragraph.alignment = alignment
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ]
            if kern != 0 { attributes[.kern] = kern }
            return NSAttributedString(string: string, attributes: attributes)
        }

        /// Draws attributed text at the cursor, flowing across page breaks —
        /// Core Text lays out as much as fits, and the loop carries the
        /// remainder onto fresh pages until the string is spent.
        private func drawParagraph(_ text: NSAttributedString, spacingAfter: CGFloat) {
            guard text.length > 0 else { return }
            let framesetter = CTFramesetterCreateWithAttributedString(text)
            var location = 0
            while location < text.length {
                ensure(24)   // room for at least one line
                let availableHeight = bottomLimit - y
                var fit = CFRange()
                let size = CTFramesetterSuggestFrameSizeWithConstraints(
                    framesetter,
                    CFRange(location: location, length: text.length - location),
                    nil,
                    CGSize(width: contentWidth, height: availableHeight),
                    &fit
                )
                guard fit.length > 0 else { startPage(); continue }

                let cg = context.cgContext
                cg.saveGState()
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: Self.pageSize.height)
                cg.scaleBy(x: 1, y: -1)
                // The frame rect lives in Core Text's flipped coordinates.
                let flipped = CGRect(x: margin,
                                     y: Self.pageSize.height - y - size.height - 2,
                                     width: contentWidth,
                                     height: size.height + 2)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: location, length: fit.length),
                    CGPath(rect: flipped, transform: nil),
                    nil
                )
                CTFrameDraw(frame, cg)
                cg.restoreGState()

                y += size.height
                location += fit.length
                if location < text.length { startPage() }
            }
            y += spacingAfter
        }
    }
}
