import Foundation
import SwiftData
import Testing
import UIKit
@testable import VersoKit

@Suite("What arrives from another app")
struct SharedCaptureShapeTests {

    @Test("Shared text and a link become one body, link last")
    func textAndLinkCompose() throws {
        let capture = SharedCapture(
            text: "  Sourdough notes  ",
            links: [try #require(URL(string: "https://example.com/loaf"))]
        )

        #expect(capture.bodyText == "Sourdough notes\nhttps://example.com/loaf")
    }

    @Test("A share with nothing in it cannot be saved")
    func emptyCaptureIsEmpty() {
        #expect(SharedCapture().isEmpty)
        #expect(SharedCapture(text: "   \n  ").isEmpty)
    }

    /// A picture with no words is the Photos case, and it has to be savable.
    @Test("A picture on its own is not an empty share")
    func imageOnlyIsNotEmpty() {
        #expect(!SharedCapture(images: [Data([0x01])]).isEmpty)
    }

    @Test("The page title the host app supplied is what the field starts as")
    func providedTitleWins() {
        let capture = SharedCapture(text: "Something else entirely", providedTitle: "How to bake bread")
        #expect(capture.suggestedTitle == "How to bake bread")
    }

    @Test("With no supplied title, the first sentence of the text is offered")
    func firstSentenceIsOffered() {
        let capture = SharedCapture(text: "Fold the dough twice. Then rest it for an hour.")
        #expect(capture.suggestedTitle == "Fold the dough twice.")
    }

    /// A bare link is the Safari case where the page had no title. A host is
    /// something to find the note by; the whole URL is not.
    @Test("A bare link falls back to its host, without the www")
    func linkFallsBackToHost() throws {
        let capture = SharedCapture(links: [try #require(URL(string: "https://www.example.com/a/b?c=d"))])
        #expect(capture.suggestedTitle == "example.com")
    }

    @Test("A share with nothing to name offers no title rather than a bad one")
    func noTitleWhenNothingToGoOn() {
        #expect(SharedCapture(images: [Data([0x01])]).suggestedTitle.isEmpty)
    }
}

@Suite("Saving a share into the library")
@MainActor
struct SharedCaptureWriterTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try VersoModelContainer.makeInMemory())
    }

    private var intelligence: IntelligenceService {
        IntelligenceService(provider: HeuristicIntelligence(), availability: .frameworkUnavailable)
    }

    @Test("Shared text lands in the library as a note with the chosen title")
    func textBecomesANote() async throws {
        let context = try makeContext()

        let note = try await SharedCaptureWriter.write(
            SharedCapture(text: "- flour\n- water\n- salt"),
            title: "Shopping",
            in: context,
            intelligence: intelligence
        )

        #expect(note.title == "Shopping")
        #expect(!note.orderedBlocks.isEmpty)

        let stored = try context.fetch(FetchDescriptor<Note>())
        #expect(stored.count == 1)
    }

    /// The title field is what the user chose. An empty one must not overwrite
    /// the title the capture path worked out for itself.
    @Test("An empty title field leaves the derived title alone")
    func emptyTitleDoesNotOverwrite() async throws {
        let context = try makeContext()

        let note = try await SharedCaptureWriter.write(
            SharedCapture(text: "# Bread\nMix and rest."),
            title: "   ",
            in: context,
            intelligence: intelligence
        )

        #expect(!note.title.isEmpty)
    }

    @Test("A shared picture is attached to the note it was shared into")
    func imageBecomesABlock() async throws {
        let context = try makeContext()

        let note = try await SharedCaptureWriter.write(
            SharedCapture(text: "The loaf", images: [Self.makeImage()]),
            title: "",
            in: context,
            intelligence: intelligence
        )

        #expect(note.orderedBlocks.contains { $0.type == .image })
        #expect((note.images ?? []).count == 1)

        let payload = try #require(note.orderedBlocks.last).decoded(as: ImagePayload.self)
        let asset = try #require(note.images?.first)
        #expect(payload.assetID == asset.id)
    }

    /// Photos shares a picture and nothing else. Without a text body there is
    /// no captured structure to build a note from, so the blank template has to
    /// carry it.
    @Test("A picture with no words still gets a page")
    func imageOnlyStillMakesANote() async throws {
        let context = try makeContext()

        let note = try await SharedCaptureWriter.write(
            SharedCapture(images: [Self.makeImage()]),
            title: "Kitchen",
            in: context,
            intelligence: intelligence
        )

        #expect(note.title == "Kitchen")
        #expect(note.orderedBlocks.contains { $0.type == .image })
    }

    @Test("Block positions are dense after a picture is appended")
    func positionsStayDense() async throws {
        let context = try makeContext()

        let note = try await SharedCaptureWriter.write(
            SharedCapture(text: "One\nTwo", images: [Self.makeImage()]),
            title: "",
            in: context,
            intelligence: intelligence
        )

        #expect(note.orderedBlocks.map(\.position) == Array(0..<note.orderedBlocks.count))
    }

    /// Rendered rather than carried as a fixture file, so the test has real
    /// bytes for `ImageStore` to decode without adding a resource to the bundle.
    private static func makeImage() -> Data {
        let size = CGSize(width: 12, height: 8)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }
}
