import Foundation
import SwiftData
import Testing
import UIKit
@testable import VersoKit

/// `BlockType.image` was declared and unimplemented from the start — the
/// registry refused it cleanly, which is right for a gap and wrong for a notes
/// app, since pasting a photo is the first thing most people try.
@Suite("Image blocks")
@MainActor
struct ImageBlockTests {

    private func makeImage(size: CGSize) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }

    @Test("The registry implements it now")
    func registryImplementsImages() {
        #expect(BlockRegistry.shared.isImplemented(.image))
        #expect(throws: Never.self) { _ = try BlockRegistry.shared.makeDefaultData(for: .image) }
    }

    @Test("A picture reaches a duplicate of its note")
    func duplicateCarriesImages() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "Album")
        context.insert(note)
        let payload = try ImageStore.importImage(
            data: makeImage(size: CGSize(width: 200, height: 100)),
            atPageWidth: 320, into: note, context: context
        )

        let copy = note.duplicated(into: context, titleSuffix: "Copy")
        #expect(ImageStore.load(payload.assetID, in: copy) != nil)
    }

    @Test("A payload round-trips")
    func roundTrip() throws {
        let payload = ImagePayload(
            assetID: UUID(),
            caption: "The kitchen table",
            displayHeight: 300,
            accessibilityDescription: "A table with a bowl on it"
        )
        let data = try BlockCoding.encode(payload)
        let decoded = try BlockCoding.decode(ImagePayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test("Height is clamped, so a bad value cannot make a page of one picture")
    func heightIsClamped() {
        #expect(ImagePayload(displayHeight: 10_000).displayHeight == ImagePayload.maximumHeight)
        #expect(ImagePayload(displayHeight: -5).displayHeight == ImagePayload.minimumHeight)
    }

    @Test("A template keeps the shape and drops the picture")
    func templateDropsTheImage() {
        let payload = ImagePayload(assetID: UUID(), caption: "Mine", displayHeight: 300)
        let reset = payload.resetForTemplate()

        #expect(reset.assetID == nil)
        #expect(reset.caption.isEmpty)
        #expect(reset.displayHeight == 300, "the space it occupied is part of the form")
    }

    /// The one that would otherwise be found by a full phone: a camera writes
    /// about 4000px and a note with a dozen of those is a problem, not a
    /// document.
    @Test("Importing downscales a large picture and attaches it to the note")
    func importDownscales() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "Album")
        context.insert(note)

        let data = makeImage(size: CGSize(width: 4_000, height: 3_000))
        let payload = try ImageStore.importImage(
            data: data, atPageWidth: 320, into: note, context: context
        )

        let assetID = try #require(payload.assetID)
        #expect(note.images?.count == 1)
        let loaded = try #require(ImageStore.load(assetID, in: note))
        #expect(max(loaded.size.width, loaded.size.height) <= ImageStore.maximumPixelSize)
        // 4:3 at 320 wide is 240 tall, and the height has to survive the resize.
        #expect(abs(payload.displayHeight - 240) < 1)
    }

    @Test("Unreadable bytes are refused rather than stored")
    func rejectsRubbish() {
        let context = ModelContext(try! VersoModelContainer.makeInMemory())
        let note = Note()
        context.insert(note)
        #expect(throws: (any Error).self) {
            _ = try ImageStore.importImage(
                data: Data("not an image".utf8), atPageWidth: 320, into: note, context: context
            )
        }
    }

    @Test("Markdown keeps the alt text")
    func markdownCarriesAlt() {
        let id = UUID()
        let payload = ImagePayload(assetID: id, accessibilityDescription: "A bowl")
        #expect(payload.markdownRepresentation == "![A bowl](\(id.uuidString).jpg)")
        #expect(ImagePayload().markdownRepresentation.isEmpty, "no picture, no tag")
    }
}
