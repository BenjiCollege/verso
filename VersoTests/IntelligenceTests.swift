import Foundation
import SwiftData
import Testing
@testable import Verso

/// The fallback is what §1 promises: the app fully usable with no Apple
/// Intelligence. So it is the half that gets tested — the model-backed path
/// cannot be exercised without hardware, and every one of its methods falls
/// through to exactly this code when it fails.
@Suite("Heuristic intelligence")
struct HeuristicIntelligenceTests {

    private let provider = HeuristicIntelligence()

    // MARK: - Titling

    @Test("A title comes from the opening line")
    func titleFromFirstLine() async {
        let digest = NoteDigest(blocks: ["Bread recipe for Saturday. Needs a long prove."])
        let title = await provider.suggestTitle(for: digest)
        #expect(title == "Bread recipe for Saturday.")
    }

    @Test("A long opening line is truncated rather than used whole")
    func longTitleIsTruncated() async throws {
        let long = (0..<40).map { "word\($0)" }.joined(separator: " ")
        let title = try #require(await provider.suggestTitle(for: NoteDigest(blocks: [long])))
        #expect(title.hasSuffix("…"))
        #expect(title.split(separator: " ").count <= 9)
    }

    @Test("An empty note gets no title rather than a bad one")
    func emptyNoteHasNoTitle() async {
        #expect(await provider.suggestTitle(for: NoteDigest()) == nil)
        #expect(await provider.suggestTitle(for: NoteDigest(blocks: ["", "  "])) == nil)
    }

    // MARK: - Tags

    /// Section 7: suggestion constrained to existing tags. A vocabulary that
    /// grows itself stops being a vocabulary.
    @Test("Only existing tags are suggested, and only ones that appear")
    func tagsAreConstrained() async {
        let digest = NoteDigest(title: "Bench day", blocks: ["Worked on fitness and had a coffee."])
        let suggested = await provider.suggestTags(for: digest, existing: ["fitness", "coffee", "gardening"])

        #expect(suggested.contains("fitness"))
        #expect(suggested.contains("coffee"))
        #expect(!suggested.contains("gardening"))
    }

    @Test("Nothing is suggested when there are no tags to suggest from")
    func noExistingTags() async {
        #expect(await provider.suggestTags(for: NoteDigest(blocks: ["anything"]), existing: []).isEmpty)
    }

    @Test("Tag matching ignores case and accents")
    func tagMatchingFolds() async {
        let digest = NoteDigest(blocks: ["Went to the CAFÉ."])
        #expect(await provider.suggestTags(for: digest, existing: ["cafe"]).contains("cafe"))
    }

    // MARK: - Summary

    @Test("A summary is at most three lines")
    func summaryIsThreeLines() async {
        let text = (0..<12).map { "Sentence number \($0) about paper and ink and binding." }.joined(separator: " ")
        let summary = await provider.summarise(NoteDigest(blocks: [text]))
        #expect(summary.count <= 3)
        #expect(!summary.isEmpty)
    }

    @Test("A short note summarises to itself rather than to nothing")
    func shortNoteSummary() async {
        let summary = await provider.summarise(NoteDigest(blocks: ["One thought. Two thoughts."]))
        #expect(summary.count == 2)
    }

    /// An extractive summary cannot invent a claim the note did not make, which
    /// for a summary is the failure that matters.
    @Test("Every summary line comes from the note")
    func summaryDoesNotInvent() async {
        let sentences = ["The oak was felled in March.", "Ink was made from the galls.", "Paper came later."]
        let summary = await provider.summarise(NoteDigest(blocks: [sentences.joined(separator: " ")]))

        for line in summary {
            let stripped = line.replacingOccurrences(of: "…", with: "")
            #expect(sentences.contains { $0.hasPrefix(stripped) || stripped.hasPrefix($0) }, "invented: \(line)")
        }
    }

    @Test("An empty note summarises to nothing")
    func emptySummary() async {
        #expect(await provider.summarise(NoteDigest()).isEmpty)
    }

    // MARK: - Actions

    @Test("Imperative lines and marked lines are found")
    func actionsAreFound() async {
        let digest = NoteDigest(blocks: [
            """
            We talked about the launch.
            - Send the deck to Priya
            TODO: book the room
            I sent the invoice yesterday.
            """,
        ])

        let actions = await provider.extractActions(from: digest)
        #expect(actions.contains { $0.contains("Send the deck") })
        #expect(actions.contains { $0.contains("book the room") })
        // Past tense is a note about what happened, not a thing to do.
        #expect(!actions.contains { $0.contains("sent the invoice") })
    }

    @Test("A note with no actions produces none rather than guessing")
    func noActions() async {
        let digest = NoteDigest(blocks: ["It rained all day and the ink took a long time to dry."])
        #expect(await provider.extractActions(from: digest).isEmpty)
    }

    @Test("Duplicate actions are collapsed")
    func actionsAreDeduplicated() async {
        let digest = NoteDigest(blocks: ["- Send the deck\n- Send the deck"])
        #expect(await provider.extractActions(from: digest).count == 1)
    }
}

@Suite("Structuring pasted text")
struct TextStructuringTests {

    private let provider = HeuristicIntelligence()

    @Test("A markdown heading becomes the title")
    func markdownTitle() async {
        let captured = await provider.structure("# Sourdough\n\nMix and wait.")
        #expect(captured.title == "Sourdough")
    }

    @Test("Bulleted lines become items")
    func bulletsBecomeItems() async {
        let captured = await provider.structure("Shopping\n- Lemons\n- Bread\n- Butter")
        #expect(captured.itemCount == 3)
        #expect(captured.sections.flatMap(\.items).map(\.label) == ["Lemons", "Bread", "Butter"])
    }

    @Test("Numbered lines become items too")
    func numberedListsBecomeItems() async {
        let captured = await provider.structure("Method\n1. Mix\n2. Prove\n3. Bake")
        #expect(captured.itemCount == 3)
    }

    /// The shapes recipes and shopping lists are actually written in.
    @Test("Quantities and units are pulled out", arguments: [
        ("2 lemons", "lemons", 2.0, String?.none),
        ("300g flour", "flour", 300.0, "g"),
        ("2 tbsp olive oil", "olive oil", 2.0, "tbsp"),
        ("Milk x2", "Milk", 2.0, String?.none),
        ("- 6 eggs", "eggs", 6.0, String?.none),
    ])
    func quantitiesAreParsed(input: String, label: String, quantity: Double, unit: String?) {
        let item = HeuristicIntelligence.parseItem(HeuristicIntelligence.stripListMarker(input))
        #expect(item.label == label)
        #expect(item.quantity == quantity)
        #expect(item.unit == unit)
    }

    /// "2024 was a good year" is not two thousand and twenty-four years.
    @Test("A year at the start of a sentence is not a quantity")
    func yearsAreNotQuantities() async {
        let captured = await provider.structure("2024 was a good year for the garden and everything in it")
        #expect(captured.itemCount == 0)
    }

    @Test("An item with no quantity keeps its whole label")
    func plainItems() {
        let item = HeuristicIntelligence.parseItem("Bread")
        #expect(item.label == "Bread")
        #expect(item.quantity == nil)
    }

    @Test("Colon-terminated lines become section headings")
    func colonHeadings() async {
        let captured = await provider.structure("""
        Ingredients:
        - Flour
        - Water
        Method:
        Mix them together.
        """)

        #expect(captured.sections.contains { $0.heading == "Ingredients" })
        #expect(captured.sections.contains { $0.heading == "Method" })
    }

    @Test("Prose stays prose")
    func proseIsPreserved() async {
        let captured = await provider.structure("A Note\n\nThis is just a paragraph of thinking out loud, at some length.")
        #expect(captured.sections.contains { $0.prose.contains("thinking out loud") })
    }

    @Test("Empty input produces an empty capture")
    func emptyInput() async {
        #expect(await provider.structure("").isEmpty)
        #expect(await provider.structure("   \n  \n ").isEmpty)
    }

    // MARK: - Becoming a note

    /// The captured note is turned into a template so it is built by the same
    /// instantiator every other template uses.
    @Test("A capture instantiates through the normal template path")
    func captureBecomesANote() async throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let captured = await provider.structure("""
        Sourdough

        Ingredients:
        - 500g flour
        - 350ml water
        - 10g salt

        Method:
        Mix, rest, fold, prove, bake.
        """)

        let note = try TemplateInstantiator.makeNote(from: captured.makeTemplate(), in: context)

        #expect(note.orderedBlocks.contains { $0.type == .checklist })
        #expect(note.orderedBlocks.contains { $0.type == .text })

        let checklist = try #require(
            try note.orderedBlocks.first { $0.type == .checklist }?.decoded(as: ChecklistPayload.self)
        )
        #expect(checklist.items.count == 3)
        #expect(checklist.items.contains { $0.label == "flour" && $0.quantity == 500 })
        #expect(checklist.shows(.quantity))
        try context.save()
    }

    @Test("A capture with one list does not sprout groups it does not need")
    func singleSectionIsUngrouped() async throws {
        let captured = await provider.structure("- Lemons\n- Bread")
        let template = captured.makeTemplate()
        let data = try BlockRegistry.shared.transcode(template.blocks[0].payload, as: .checklist)
        let payload = try BlockCoding.decode(ChecklistPayload.self, from: data)

        #expect(payload.groupBy == .none)
        #expect(payload.items.count == 2)
    }

    @Test("A capture with nothing in it still makes a usable note")
    func emptyCaptureIsStillANote() async throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try TemplateInstantiator.makeNote(from: CapturedNote().makeTemplate(), in: context)
        #expect(note.orderedBlocks.count == 1)
        #expect(note.orderedBlocks[0].type == .text)
    }
}

@Suite("Note digest")
struct NoteDigestTests {

    @Test("A digest is the note's readable text")
    func digestReadsTheNote() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "Title")
        context.insert(note)

        for payload in [try Block(TextPayload(plain: "First")), try Block(HeadingPayload(level: .two, text: "Second"))] {
            context.insert(payload)
            note.append(payload)
        }

        let digest = NoteDigest(note)
        #expect(digest.title == "Title")
        #expect(digest.blocks == ["First", "Second"])
        #expect(digest.text.contains("First"))
    }

    /// Nothing in the intelligence layer may read a locked note — not even to
    /// title it.
    @Test("A locked note digests to nothing")
    func lockedNotesAreOpaque() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "Private")
        context.insert(note)
        let block = try Block(TextPayload(plain: "something personal"))
        context.insert(block)
        note.append(block)

        note.isLocked = true
        let digest = NoteDigest(note)

        #expect(digest.isEmpty)
        #expect(!digest.text.contains("personal"))
        #expect(!digest.text.contains("Private"))
    }
}

@Suite("Search")
struct SemanticIndexTests {

    private let index = SemanticIndex()

    private func entry(_ title: String, _ text: String, locked: Bool = false) -> SemanticIndex.Entry {
        SemanticIndex.Entry(noteID: UUID(), title: title, text: text, isLocked: locked)
    }

    @Test("A literal match is found")
    func literalMatch() {
        let entries = [entry("Sourdough", "Flour, water, salt."), entry("Taxes", "Receipts and forms.")]
        let hits = index.search("flour", in: entries)

        #expect(hits.count == 1)
        #expect(hits[0].noteID == entries[0].noteID)
    }

    @Test("A title match outranks a body match")
    func titleOutranksBody() {
        let entries = [
            entry("Nothing", "The word sourdough appears here in the body."),
            entry("Sourdough", "Something else entirely."),
        ]
        let hits = index.search("sourdough", in: entries)
        #expect(hits.first?.noteID == entries[1].noteID)
    }

    @Test("Every word in the query has to appear somewhere")
    func allWordsMustMatch() {
        let entries = [entry("Bread", "Flour and water.")]
        #expect(index.search("flour", in: entries).count == 1)
        #expect(index.search("flour helicopter", in: entries).isEmpty)
    }

    /// Section 7: locked and hidden notes are excluded from indexing, and
    /// search is indexing by another name.
    @Test("Locked notes never appear in results")
    func lockedNotesAreExcluded() {
        let entries = [entry("Diary", "something personal", locked: true)]
        #expect(index.search("personal", in: entries).isEmpty)
        #expect(index.search("Diary", in: entries).isEmpty)
    }

    @Test("Search ignores case and accents")
    func searchFolds() {
        let entries = [entry("Café", "Went for a coffee.")]
        #expect(!index.search("cafe", in: entries).isEmpty)
        #expect(!index.search("COFFEE", in: entries).isEmpty)
    }

    @Test("An empty query matches nothing rather than everything")
    func emptyQuery() {
        let entries = [entry("Anything", "at all")]
        #expect(index.search("", in: entries).isEmpty)
        #expect(index.search("   ", in: entries).isEmpty)
    }

    @Test("Results carry an excerpt to show under the title")
    func hitsHaveExcerpts() throws {
        let entries = [entry("Bread", "Flour and water.\nSalt comes later.")]
        let hit = try #require(index.search("salt", in: entries).first)
        #expect(hit.excerpt.contains("Salt"))
    }

    /// Lexical scoring carries the whole feature where sentence embeddings are
    /// unavailable, rather than half of it.
    @Test("Search works whether or not embeddings are available")
    func lexicalCarriesTheFeature() {
        let entries = [entry("Bread", "Flour and water.")]
        #expect(!index.search("bread", in: entries).isEmpty)
    }
}
