import Foundation
import PDFKit
import PencilKit
import UIKit

/// Getting an annotated document back out.
///
/// Section 7 asks for both flattened and layered export, and the distinction
/// matters: flattened is what you send someone, layered is what you keep.
enum DocumentExporter {

    enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// Annotations burned into the page. Looks the same everywhere,
        /// including in software that has never heard of PDF annotations.
        case flattened
        /// Annotations as real PDF annotations. Another app can select, move
        /// or delete them — which is the point, and also the risk.
        case layered

        var id: String { rawValue }

        var displayName: LocalizedStringResource {
            switch self {
            case .flattened: "Flattened"
            case .layered: "Layered"
            }
        }

        var summary: LocalizedStringResource {
            switch self {
            case .flattened: "Marks are part of the page. Looks identical anywhere."
            case .layered: "Marks stay editable in other PDF apps."
            }
        }
    }

    /// Colours are resolved from the theme at export time rather than stored,
    /// so a document exported today matches the note as it looks today.
    static func color(for role: DocumentAnnotations.HighlightColor, theme: Theme) -> UIColor {
        switch role {
        case .accent: UIColor(theme.accent)
        case .gilt: UIColor(theme.gilt)
        case .ink: UIColor(theme.ink)
        }
    }

    static func export(
        _ payload: AttachmentPayload,
        mode: Mode,
        theme: Theme
    ) throws -> Data {
        guard let document = DocumentStore.document(for: payload) else {
            throw DocumentError.missingFile
        }

        return switch mode {
        case .layered: try layered(document, payload: payload, theme: theme)
        case .flattened: try flattened(document, payload: payload, theme: theme)
        }
    }

    // MARK: - Layered

    /// Adds real `PDFAnnotation`s to a copy of the document.
    private static func layered(
        _ document: PDFDocument,
        payload: AttachmentPayload,
        theme: Theme
    ) throws -> Data {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let size = DocumentStore.pageSize(of: page)

            for highlight in payload.annotations.highlights(onPage: index) {
                for rect in highlight.rects where rect.isMeaningful {
                    let annotation = PDFAnnotation(
                        bounds: rect.rect(in: size),
                        forType: .highlight,
                        withProperties: nil
                    )
                    annotation.color = color(for: highlight.color, theme: theme).withAlphaComponent(0.4)
                    page.addAnnotation(annotation)
                }
            }

            // Ink becomes one annotation per stroke, which is what keeps each
            // stroke individually erasable in another app.
            if let data = payload.annotations.drawing(onPage: index),
               let drawing = try? PKDrawing(data: data) {
                for stroke in drawing.strokes {
                    guard let annotation = inkAnnotation(for: stroke, pageSize: size, theme: theme) else { continue }
                    page.addAnnotation(annotation)
                }
            }
        }

        guard let data = document.dataRepresentation() else { throw DocumentError.exportFailed }
        return data
    }

    private static func inkAnnotation(for stroke: PKStroke, pageSize: CGSize, theme: Theme) -> PDFAnnotation? {
        let points = stroke.path.map(\.location)
        guard points.count > 1 else { return nil }

        let path = UIBezierPath()
        path.move(to: flip(points[0], in: pageSize))
        for point in points.dropFirst() {
            path.addLine(to: flip(point, in: pageSize))
        }

        let annotation = PDFAnnotation(bounds: CGRect(origin: .zero, size: pageSize), forType: .ink, withProperties: nil)
        annotation.color = UIColor(theme.ink)
        annotation.border = PDFBorder()
        annotation.border?.lineWidth = 2
        annotation.add(path)
        return annotation
    }

    /// PDF pages have their origin at the bottom left; everything drawn on
    /// screen has it at the top left. Getting this backwards mirrors every
    /// annotation vertically, which is the classic PDF bug.
    private static func flip(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x, y: size.height - point.y)
    }

    // MARK: - Flattened

    /// Redraws every page with its annotations painted on.
    private static func flattened(
        _ document: PDFDocument,
        payload: AttachmentPayload,
        theme: Theme
    ) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw DocumentError.exportFailed }

        var mediaBox = CGRect(origin: .zero, size: CGSize(width: 612, height: 792))
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw DocumentError.exportFailed
        }

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let size = DocumentStore.pageSize(of: page)

            // Each page keeps its own size: a document mixing portrait and
            // landscape pages must not be forced into one shape.
            let box = CGRect(origin: .zero, size: size)
            context.beginPDFPage([kCGPDFContextMediaBox as String: NSValue(cgRect: box)] as CFDictionary)

            context.saveGState()
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()

            drawHighlights(payload.annotations.highlights(onPage: index), size: size, theme: theme, in: context)
            drawInk(payload.annotations.drawing(onPage: index), size: size, theme: theme, in: context)

            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    private static func drawHighlights(
        _ highlights: [DocumentAnnotations.Highlight],
        size: CGSize,
        theme: Theme,
        in context: CGContext
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        // Multiply, so the text underneath stays legible through the colour
        // rather than being painted over.
        context.setBlendMode(.multiply)

        for highlight in highlights {
            context.setFillColor(color(for: highlight.color, theme: theme).withAlphaComponent(0.35).cgColor)
            for rect in highlight.rects where rect.isMeaningful {
                context.fill(rect.rect(in: size))
            }
        }
    }

    private static func drawInk(_ data: Data?, size: CGSize, theme: Theme, in context: CGContext) {
        guard let data, let drawing = try? PKDrawing(data: data) else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(UIColor(theme.ink).cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in drawing.strokes {
            let points = stroke.path.map { flip($0.location, in: size) }
            guard points.count > 1 else { continue }
            context.addLines(between: points)
            context.strokePath()
        }
    }

    // MARK: - Filenames

    static func fileName(for payload: AttachmentPayload, mode: Mode) -> String {
        let base = payload.fileName.isEmpty
            ? String(localized: "Document")
            : (payload.fileName as NSString).deletingPathExtension
        let suffix = mode == .flattened
            ? String(localized: "annotated")
            : String(localized: "marked up")
        return "\(base) (\(suffix)).pdf"
    }
}
