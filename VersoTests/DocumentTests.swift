import CoreGraphics
import Foundation
import PDFKit
import Testing
import UIKit
@testable import VersoKit

@Suite("Document annotations")
struct DocumentAnnotationTests {

    private let pageSize = CGSize(width: 612, height: 792)

    // MARK: - Normalised rects

    /// Storing points would tie every highlight to the screen it was made on.
    @Test("A rect normalises and comes back unchanged")
    func normalisationRoundTrips() {
        let original = CGRect(x: 61.2, y: 79.2, width: 306, height: 158.4)
        let restored = NormalisedRect(original, in: pageSize).rect(in: pageSize)

        #expect(abs(restored.minX - original.minX) < 0.001)
        #expect(abs(restored.minY - original.minY) < 0.001)
        #expect(abs(restored.width - original.width) < 0.001)
        #expect(abs(restored.height - original.height) < 0.001)
    }

    /// The point of normalising: the same annotation on a phone and an iPad.
    @Test("A rect lands proportionally at any page size")
    func normalisationSurvivesResizing() {
        let normalised = NormalisedRect(CGRect(x: 153, y: 198, width: 306, height: 396), in: pageSize)
        let onPhone = normalised.rect(in: CGSize(width: 306, height: 396))

        #expect(abs(onPhone.minX - 76.5) < 0.001)
        #expect(abs(onPhone.width - 153) < 0.001)
    }

    @Test("A zero-sized page does not divide by zero")
    func zeroPageIsSafe() {
        let normalised = NormalisedRect(CGRect(x: 10, y: 10, width: 10, height: 10), in: .zero)
        #expect(normalised.width == 0)
        #expect(!normalised.isMeaningful)
    }

    @Test("A vanishingly small rect is not worth keeping")
    func tinyRectsAreRejected() {
        var annotations = DocumentAnnotations()
        annotations.add(.init(page: 0, rects: [NormalisedRect(x: 0, y: 0, width: 0, height: 0)]))
        #expect(annotations.highlights.isEmpty)

        annotations.add(.init(page: 0, rects: [NormalisedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02)]))
        #expect(annotations.highlights.count == 1)
    }

    // MARK: - Ink

    @Test("Ink is stored and replaced per page")
    func inkIsPerPage() {
        var annotations = DocumentAnnotations()
        annotations.setDrawing(Data([0x01]), onPage: 0)
        annotations.setDrawing(Data([0x02]), onPage: 3)

        #expect(annotations.drawing(onPage: 0) == Data([0x01]))
        #expect(annotations.drawing(onPage: 3) == Data([0x02]))
        #expect(annotations.drawing(onPage: 1) == nil)

        annotations.setDrawing(Data([0x09]), onPage: 0)
        #expect(annotations.ink.count == 2)
        #expect(annotations.drawing(onPage: 0) == Data([0x09]))
    }

    /// Erasing everything on a page should leave nothing behind, not an empty
    /// record that still marks the page as annotated.
    @Test("Clearing a page's ink removes it entirely")
    func clearingInkRemovesTheRecord() {
        var annotations = DocumentAnnotations()
        annotations.setDrawing(Data([0x01]), onPage: 2)
        annotations.setDrawing(Data(), onPage: 2)

        #expect(annotations.ink.isEmpty)
        #expect(!annotations.annotatedPages.contains(2))
    }

    @Test("Pages are kept in order however they were drawn on")
    func inkIsOrdered() {
        var annotations = DocumentAnnotations()
        for page in [5, 1, 3] {
            annotations.setDrawing(Data([0x01]), onPage: page)
        }
        #expect(annotations.ink.map(\.page) == [1, 3, 5])
    }

    // MARK: - Highlights

    @Test("Highlights are found by page")
    func highlightsByPage() {
        var annotations = DocumentAnnotations()
        annotations.add(.init(page: 0, rects: [rect()], text: "first"))
        annotations.add(.init(page: 2, rects: [rect()], text: "second"))

        #expect(annotations.highlights(onPage: 0).count == 1)
        #expect(annotations.highlights(onPage: 1).isEmpty)
        #expect(annotations.highlights(onPage: 2).first?.text == "second")
    }

    @Test("A highlight can be removed")
    func highlightsAreRemovable() {
        var annotations = DocumentAnnotations()
        let highlight = DocumentAnnotations.Highlight(page: 0, rects: [rect()])
        annotations.add(highlight)
        annotations.removeHighlight(id: highlight.id)
        #expect(annotations.highlights.isEmpty)
    }

    /// A highlight across a paragraph break is several rectangles, not one that
    /// swallows the margin.
    @Test("A highlight carries one rect per line")
    func highlightsAreMultiRect() {
        var annotations = DocumentAnnotations()
        annotations.add(.init(page: 0, rects: [rect(y: 0.5), rect(y: 0.45), rect(y: 0.4)]))
        #expect(annotations.highlights[0].rects.count == 3)
    }

    /// Highlighted passages are the part of a document that belongs to the
    /// note, so they are what search and export see.
    @Test("Highlighted text comes back in reading order")
    func highlightedTextIsOrdered() {
        var annotations = DocumentAnnotations()
        annotations.add(.init(page: 1, rects: [rect(y: 0.5)], text: "third"))
        annotations.add(.init(page: 0, rects: [rect(y: 0.2)], text: "second"))
        annotations.add(.init(page: 0, rects: [rect(y: 0.1)], text: "first"))

        #expect(annotations.highlightedText == ["first", "second", "third"])
    }

    @Test("Annotated pages cover both layers")
    func annotatedPagesCoverBoth() {
        var annotations = DocumentAnnotations()
        annotations.setDrawing(Data([0x01]), onPage: 1)
        annotations.add(.init(page: 4, rects: [rect()]))

        #expect(annotations.annotatedPages == [1, 4])
        #expect(!annotations.isEmpty)
        #expect(DocumentAnnotations().isEmpty)
    }

    @Test("Annotations survive encode/decode")
    func codingRoundTrips() throws {
        var annotations = DocumentAnnotations()
        annotations.setDrawing(Data([0x01, 0x02]), onPage: 2)
        annotations.add(.init(page: 2, rects: [rect(), rect(y: 0.3)], color: .gilt, text: "a passage"))

        #expect(try BlockCoding.decode(
            DocumentAnnotations.self,
            from: BlockCoding.encode(annotations)
        ) == annotations)
    }

    private func rect(y: Double = 0.5) -> NormalisedRect {
        NormalisedRect(x: 0.1, y: y, width: 0.6, height: 0.02)
    }
}

@Suite("Attachment payload")
struct AttachmentPayloadTests {

    @Test("Payload survives encode/decode")
    func roundTrip() throws {
        var annotations = DocumentAnnotations()
        annotations.add(.init(page: 0, rects: [NormalisedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02)], text: "kept"))

        let original = AttachmentPayload(
            assetID: UUID(),
            fileName: "Lease.pdf",
            pageCount: 12,
            byteCount: 240_000,
            thumbnail: Data([0xFF, 0xD8]),
            annotations: annotations
        )

        #expect(try BlockCoding.decode(AttachmentPayload.self, from: BlockCoding.encode(original)) == original)
    }

    @Test("An empty attachment says so")
    func emptyAttachment() {
        let payload = AttachmentPayload()
        #expect(payload.isEmpty)
        #expect(payload.displayName == "Document")
        #expect(!AttachmentPayload(assetID: UUID()).isEmpty)
    }

    @Test("Negative counts from a malformed payload are clamped")
    func countsAreClamped() {
        #expect(AttachmentPayload(pageCount: -5).pageCount == 0)
        #expect(AttachmentPayload(byteCount: -1).byteCount == 0)
    }

    /// The passages somebody marked are the part of the document that belongs
    /// to the note.
    @Test("Highlighted passages are what search and export see")
    func highlightsAreTheContent() {
        var annotations = DocumentAnnotations()
        annotations.add(.init(
            page: 0,
            rects: [NormalisedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02)],
            text: "the clause about the boiler"
        ))
        let payload = AttachmentPayload(fileName: "Lease.pdf", annotations: annotations)

        #expect(payload.plainTextRepresentation.contains("boiler"))
        #expect(payload.markdownRepresentation.contains("> the clause about the boiler"))
        #expect(payload.markdownRepresentation.contains("Lease.pdf"))
    }

    /// A template carries the shape of a note, not somebody's lease.
    @Test("A template keeps the name and drops the document")
    func templateReset() {
        var annotations = DocumentAnnotations()
        annotations.add(.init(page: 0, rects: [NormalisedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.02)]))

        let reset = AttachmentPayload(
            assetID: UUID(),
            fileName: "Lease.pdf",
            pageCount: 12,
            annotations: annotations
        ).resetForTemplate()

        #expect(reset.assetID == nil)
        #expect(reset.annotations.isEmpty)
        #expect(reset.fileName == "Lease.pdf")
    }

    @Test("A thumbnail stays small enough to sit in a block payload")
    func thumbnailBudget() {
        #expect(AttachmentPayload.maximumThumbnailBytes < 100_000)
    }

    @Test("Both export modes are offered and named distinctly")
    func exportModes() {
        #expect(DocumentExporter.Mode.allCases.count == 2)
        let payload = AttachmentPayload(fileName: "Lease.pdf")

        let flattened = DocumentExporter.fileName(for: payload, mode: .flattened)
        let layered = DocumentExporter.fileName(for: payload, mode: .layered)

        #expect(flattened != layered)
        #expect(flattened.hasSuffix(".pdf"))
        #expect(flattened.contains("Lease"))
        #expect(!flattened.contains(".pdf ("), "the original extension should not be doubled up")
    }
}

/// The page raster cache.
///
/// `DocumentStore.image` is called from `body`, so it runs on every pass — and
/// `body` re-runs on every tick of a highlight drag. Without a cache, dragging
/// across a paragraph re-rendered the whole page at 2× for each frame.
///
/// What is worth testing is not the speed but the *identity*: a cache that
/// returns the wrong page is far worse than no cache.
@Suite("Document raster cache")
struct DocumentRasterCacheTests {

    /// A one-page PDF of a given size, written to a real file — the cache keys
    /// on `documentURL`, so an in-memory document would not exercise it.
    private func makeDocument(width: CGFloat, height: CGFloat) throws -> PDFDocument {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var media = bounds
        let context = try #require(CGContext(consumer: consumer, mediaBox: &media, nil))
        context.beginPDFPage(nil)
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.endPDFPage()
        context.closePDF()

        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try (data as Data).write(to: url)
        return try #require(PDFDocument(url: url))
    }

    @Test("The same page at the same width comes back identical")
    func repeatedRenderIsCached() throws {
        // The document is held for the length of the test on purpose:
        // `PDFPage.document` is a back-reference, and a page whose document has
        // gone reports `nil` — at which point the cache silently stops working
        // because it can no longer identify what it is caching.
        let document = try makeDocument(width: 200, height: 300)
        let page = try #require(document.page(at: 0))

        let first = try #require(DocumentStore.image(of: page, fittingWidth: 120))
        let second = try #require(DocumentStore.image(of: page, fittingWidth: 120))

        #expect(first === second)
    }

    /// Rotating the device asks for a different width. Serving the old raster
    /// would show the portrait rendering stretched.
    @Test("A different width is a different rendering")
    func widthIsPartOfTheIdentity() throws {
        let document = try makeDocument(width: 200, height: 300)
        let page = try #require(document.page(at: 0))

        let narrow = try #require(DocumentStore.image(of: page, fittingWidth: 120))
        let wide = try #require(DocumentStore.image(of: page, fittingWidth: 240))

        #expect(narrow !== wide)
        #expect(narrow.size.width != wide.size.width)
    }

    /// The reason the key is the document's URL and not `ObjectIdentifier`:
    /// an address is reused, so a closed document's cached pages could be
    /// served to whatever is allocated where it used to be.
    @Test("Two documents never serve each other's pages")
    func documentsDoNotCollide() throws {
        let tallDocument = try makeDocument(width: 200, height: 400)
        let squatDocument = try makeDocument(width: 200, height: 100)
        let tall = try #require(tallDocument.page(at: 0))
        let squat = try #require(squatDocument.page(at: 0))

        let a = try #require(DocumentStore.image(of: tall, fittingWidth: 100))
        let b = try #require(DocumentStore.image(of: squat, fittingWidth: 100))

        #expect(a !== b)
        // Same requested width, different page shapes — so a collision would
        // show up as the wrong height.
        #expect(a.size.height != b.size.height)
    }
}
