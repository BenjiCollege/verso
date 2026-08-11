import CoreServices
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Turning a note into something that leaves the app.
///
/// Markdown, PDF and an animated share card. All three go out through
/// `ShareLink` as files — there is no upload, no shortened link and no server,
/// which is the point.
enum NoteExporter {

    enum Format: String, CaseIterable, Identifiable, Sendable {
        case markdown
        case pdf
        case shareCard

        var id: String { rawValue }

        var displayName: LocalizedStringResource {
            switch self {
            case .markdown: "Markdown"
            case .pdf: "PDF"
            case .shareCard: "Animated Card"
            }
        }

        var summary: LocalizedStringResource {
            switch self {
            case .markdown: "Plain text with structure. Opens anywhere."
            case .pdf: "The page as it looks, in your theme."
            case .shareCard: "A short animation of the note revealing itself."
            }
        }

        var systemImage: String {
            switch self {
            case .markdown: "doc.plaintext"
            case .pdf: "doc.richtext"
            case .shareCard: "sparkles.rectangle.stack"
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .pdf: "pdf"
            case .shareCard: "gif"
            }
        }
    }

    // MARK: - Markdown

    /// Walks the blocks and asks the registry. No block type is named here.
    static func markdown(for note: Note, registry: BlockRegistry = .shared) -> String {
        var lines: [String] = []

        if !note.title.isEmpty {
            lines.append("# \(note.title)")
        }

        for block in note.orderedBlocks {
            let text = registry.markdown(for: block)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            lines.append(text)
        }

        // A trailing attribution, kept to one line and honest about there being
        // no service behind it.
        lines.append("")
        lines.append("_Exported from Verso on \(note.modifiedAt.formatted(date: .abbreviated, time: .omitted))._")

        return lines.joined(separator: "\n\n")
    }

    // MARK: - Files

    static func fileName(for note: Note, format: Format) -> String {
        let base = note.title.isEmpty ? String(localized: "Untitled") : note.title
        let cleaned = base
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Note" : String(cleaned.prefix(80))) + "." + format.fileExtension
    }

    static func write(_ data: Data, for note: Note, format: Format) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: fileName(for: note, format: format))
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - PDF

    /// Renders the note's page into a paginated PDF.
    ///
    /// The page is drawn in the note's own theme, so an exported PDF looks like
    /// the note rather than like a word processor's idea of one.
    @MainActor
    static func pdf(
        for note: Note,
        theme: Theme,
        stock: Stock,
        pageSize: CGSize = CGSize(width: 595, height: 842)
    ) -> Data? {
        let content = ExportPage(note: note, width: pageSize.width)
            .versoTheme(theme, stock: stock)
            .environment(\.themeCatalog, ThemeCatalog.shared)
            .frame(width: pageSize.width)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: nil)

        var output: Data?
        renderer.render { size, draw in
            var bounds = CGRect(origin: .zero, size: pageSize)
            let data = NSMutableData()

            guard let consumer = CGDataConsumer(data: data),
                  let context = CGContext(consumer: consumer, mediaBox: &bounds, nil)
            else { return }

            // The content is one tall column; it is sliced into pages by
            // translating the context, which keeps text vector rather than
            // rasterising each page.
            let pageCount = max(1, Int(ceil(size.height / pageSize.height)))
            for page in 0..<pageCount {
                context.beginPDFPage(nil)
                context.saveGState()
                context.translateBy(x: 0, y: -CGFloat(page) * pageSize.height)
                draw(context)
                context.restoreGState()
                context.endPDFPage()
            }
            context.closePDF()
            output = data as Data
        }
        return output
    }

    // MARK: - Animated share card

    /// The note revealing itself, as an animated GIF.
    ///
    /// A GIF rather than a video: it needs no export session, no temporary
    /// asset writer and no permissions, it plays inline in every messaging app,
    /// and it is written with ImageIO, which is already here. Nothing is
    /// uploaded to make it.
    @MainActor
    static func shareCard(
        for note: Note,
        theme: Theme,
        stock: Stock,
        style: RevealStyle,
        size: CGSize = CGSize(width: 900, height: 1200),
        frameCount: Int = 36,
        frameDuration: TimeInterval = 1.0 / 24
    ) -> Data? {
        let plan = RevealPlan.plan(for: style)
        let blockCount = note.orderedBlocks.count + 1
        // A still card for `none`, which is also what Reduce Motion resolves to.
        let duration = max(plan.totalDuration(unitCount: blockCount), 0.001)
        let frames = plan.style == .none ? 1 : frameCount

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            frames,
            nil
        ) else { return nil }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        for frame in 0..<frames {
            let elapsed = frames == 1 ? duration : duration * Double(frame) / Double(frames - 1)
            let content = ShareCard(note: note, plan: plan, elapsed: elapsed, size: size)
                .versoTheme(theme, stock: stock)
                .environment(\.themeCatalog, ThemeCatalog.shared)
                .frame(width: size.width, height: size.height)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            guard let image = renderer.cgImage else { continue }

            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: frameDuration],
            ] as CFDictionary)
        }

        // Hold on the finished note, so the card does not snap back to blank
        // the instant it completes.
        if frames > 1, let renderer = ImageRenderer(
            content: ShareCard(note: note, plan: plan, elapsed: duration, size: size)
                .versoTheme(theme, stock: stock)
                .environment(\.themeCatalog, ThemeCatalog.shared)
                .frame(width: size.width, height: size.height)
        ).cgImage {
            CGImageDestinationAddImage(destination, renderer, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 1.4],
            ] as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// The layout used for PDF export. One tall column, sliced into pages.
private struct ExportPage: View {
    let note: Note
    let width: CGFloat

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.regular) {
            if !note.title.isEmpty {
                Text(note.title)
                    .versoText(.display)
                    .foregroundStyle(theme.ink)
            }

            ForEach(note.orderedBlocks) { block in
                BlockRenderer(block: block)
                    .disabled(true)
                    .allowsHitTesting(false)
            }
        }
        .padding(Layout.Space.vast)
        .frame(width: width, alignment: .leading)
        .background(theme.stock)
    }
}

/// One frame of the animated card.
private struct ShareCard: View {
    let note: Note
    let plan: RevealPlan
    let elapsed: TimeInterval
    let size: CGSize

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.stock
            PageBackground()

            VStack(alignment: .leading, spacing: Layout.Space.regular) {
                if !note.title.isEmpty {
                    Text(note.title)
                        .versoText(.display)
                        .foregroundStyle(theme.ink)
                        .revealed(plan: plan, index: 0, elapsed: elapsed)
                }

                ForEach(Array(note.orderedBlocks.prefix(8).enumerated()), id: \.element.id) { index, block in
                    BlockRenderer(block: block)
                        .disabled(true)
                        .allowsHitTesting(false)
                        .revealed(plan: plan, index: index + 1, elapsed: elapsed)
                }

                Spacer(minLength: 0)
            }
            .padding(Layout.Space.vast)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
