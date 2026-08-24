import Foundation
import PencilKit
import Testing
@testable import VersoKit

/// Handwriting reaching search.
///
/// The bug these guard against is a quiet one: a sketch used to contribute the
/// literal word "Sketch" to the index, so a handwritten page was unfindable by
/// anything on it *and* was returned by a search for "sketch". Both halves of
/// that are worth a test, because neither looks broken from the outside.
@Suite("Handwriting search")
struct HandwritingSearchTests {

    @Test("A drawing contributes the words that were written on it")
    func recognisedTextReachesSearch() {
        let payload = SketchPayload(
            drawing: Data([0x01]),
            recognisedText: "milk and bread"
        )

        #expect(payload.plainTextRepresentation == "milk and bread")
    }

    /// A diagram is still a drawing. Falling back to "Sketch" is what keeps an
    /// unreadable page from vanishing out of the note's summary entirely.
    @Test("A drawing with no readable words still says it is a sketch")
    func unreadableFallsBack() {
        let payload = SketchPayload(drawing: Data([0x01]), recognisedText: "")

        #expect(payload.plainTextRepresentation == "Sketch")
    }

    @Test("An empty canvas contributes nothing at all")
    func emptyContributesNothing() {
        #expect(SketchPayload().plainTextRepresentation.isEmpty)
        // Even if stale words somehow survived, no ink means nothing to find.
        #expect(SketchPayload(drawing: Data(), recognisedText: "ghost").plainTextRepresentation.isEmpty)
    }

    /// Every sketch drawn before this feature existed decodes without the key.
    /// Getting this wrong would not fail loudly — it would throw during decode
    /// and the block would render as broken.
    @Test("A sketch saved before handwriting was readable still decodes")
    func decodesWithoutTheNewKey() throws {
        let legacy = Data(#"{"drawing":"AQID","height":240}"#.utf8)
        let payload = try BlockCoding.decode(SketchPayload.self, from: legacy)

        #expect(payload.recognisedText.isEmpty)
        #expect(payload.height == 240)
        #expect(!payload.isEmpty)
    }

    @Test("Recognised text survives a round trip through the payload")
    func roundTrips() throws {
        let original = SketchPayload(drawing: Data([0x09]), height: 300, recognisedText: "shopping list")
        let data = try BlockCoding.encode(original)
        let decoded = try BlockCoding.decode(SketchPayload.self, from: data)

        #expect(decoded.recognisedText == "shopping list")
    }

    /// A template carries the shape of a note, not its contents — and the words
    /// read off somebody's handwriting are very much contents.
    @Test("A template keeps the size and loses the handwriting")
    func templateDropsTheWords() {
        let payload = SketchPayload(drawing: Data([0x01]), height: 400, recognisedText: "private thoughts")
        let template = payload.resetForTemplate()

        #expect(template.recognisedText.isEmpty)
        #expect(template.drawing.isEmpty)
        #expect(template.height == 400)
    }

    /// Recognition is a guess; the ink is the record. Markdown deliberately does
    /// not present read-back words as if the user had typed them.
    @Test("Export does not pass recognised words off as written text")
    func markdownStaysHonest() {
        let payload = SketchPayload(drawing: Data([0x01]), recognisedText: "guessed words")

        #expect(!payload.markdownRepresentation.contains("guessed words"))
    }

    @Test("An empty drawing recognises as nothing rather than failing")
    func emptyDrawingRecognisesEmpty() async {
        #expect(await InkRecognition.text(in: PKDrawing()).isEmpty)
    }
}

/// The registry is what carries a sketch's words to every index in the app, so
/// it is worth asserting the connection rather than assuming it.
@Suite("Handwriting reaches the index")
struct HandwritingIndexTests {

    @Test("The registry reads handwriting out of a sketch block")
    func registryReadsIt() throws {
        let payload = SketchPayload(drawing: Data([0x01]), recognisedText: "meeting notes")
        let data = try BlockCoding.encode(payload)

        #expect(try BlockRegistry.shared.plainText(data, as: .sketch) == "meeting notes")
    }
}
