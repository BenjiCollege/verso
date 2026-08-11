import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Link index")
struct LinkIndexTests {

    private func makeNote(
        title: String,
        body: NSAttributedString,
        in context: ModelContext
    ) throws -> Note {
        let note = Note(title: title)
        context.insert(note)
        let block = try Block(TextPayload(semantic: body))
        context.insert(block)
        note.append(block)
        return note
    }

    @Test("A bracketed title resolves to the note it names")
    func resolvesByTitle() async throws {
        let container = try VersoModelContainer.makeInMemory()
        let context = ModelContext(container)

        let target = try makeNote(title: "Ledger", body: NSAttributedString(string: ""), in: context)
        let source = try makeNote(
            title: "Journal",
            body: NSAttributedString(string: "carried forward from [[Ledger]]"),
            in: context
        )
        try context.save()

        let graph = await LinkIndexBuilder(modelContainer: container).build()

        #expect(graph.links(from: source.id) == [target.id])
        #expect(graph.backlinks(to: target.id) == [source.id])
        #expect(graph.unresolved[source.id] == nil)
    }

    @Test("Matching a title ignores case")
    func titleMatchIsCaseInsensitive() async throws {
        let container = try VersoModelContainer.makeInMemory()
        let context = ModelContext(container)

        let target = try makeNote(title: "Iron Gall", body: NSAttributedString(string: ""), in: context)
        let source = try makeNote(
            title: "Notes",
            body: NSAttributedString(string: "see [[iron gall]]"),
            in: context
        )
        try context.save()

        let graph = await LinkIndexBuilder(modelContainer: container).build()
        #expect(graph.backlinks(to: target.id) == [source.id])
    }

    /// The attribute is the durable half of a link: rename the target and the
    /// bracketed text goes stale, but the edge must not.
    @Test("A stored link attribute resolves even when the title no longer matches")
    func resolvesByAttributeAfterRename() async throws {
        let container = try VersoModelContainer.makeInMemory()
        let context = ModelContext(container)

        let target = try makeNote(title: "Renamed Later", body: NSAttributedString(string: ""), in: context)

        let body = NSMutableAttributedString(string: "see [[Old Name]]")
        body.addAttribute(
            VersoTextAttribute.noteLink,
            value: target.id.uuidString,
            range: NSRange(location: 4, length: 12)
        )
        let source = try makeNote(title: "Source", body: body, in: context)
        try context.save()

        let graph = await LinkIndexBuilder(modelContainer: container).build()

        #expect(graph.backlinks(to: target.id) == [source.id])
        // The bracketed text still matches nothing, and is offered as a note
        // the user could create.
        #expect(graph.unresolved[source.id] == ["Old Name"])
    }

    @Test("A link to nothing is recorded as unresolved, not dropped")
    func unresolvedLinkIsRecorded() async throws {
        let container = try VersoModelContainer.makeInMemory()
        let context = ModelContext(container)

        let source = try makeNote(
            title: "Source",
            body: NSAttributedString(string: "one day [[Somewhere]]"),
            in: context
        )
        try context.save()

        let graph = await LinkIndexBuilder(modelContainer: container).build()

        #expect(graph.links(from: source.id).isEmpty)
        #expect(graph.unresolved[source.id] == ["Somewhere"])
    }

    @Test("A note linking to itself is not its own backlink")
    func selfLinksAreDropped() async throws {
        let container = try VersoModelContainer.makeInMemory()
        let context = ModelContext(container)

        let note = try makeNote(
            title: "Recursive",
            body: NSAttributedString(string: "see [[Recursive]]"),
            in: context
        )
        try context.save()

        let graph = await LinkIndexBuilder(modelContainer: container).build()
        #expect(graph.backlinks(to: note.id).isEmpty)
        #expect(graph.links(from: note.id).isEmpty)
    }

    @Test("Editing one note repairs only that note's edges")
    func incrementalUpdate() async throws {
        let container = try VersoModelContainer.makeInMemory()
        let context = ModelContext(container)

        let first = try makeNote(title: "First", body: NSAttributedString(string: ""), in: context)
        let second = try makeNote(title: "Second", body: NSAttributedString(string: ""), in: context)
        let source = try makeNote(
            title: "Source",
            body: NSAttributedString(string: "[[First]]"),
            in: context
        )
        try context.save()

        let builder = LinkIndexBuilder(modelContainer: container)
        var graph = await builder.build()
        #expect(graph.backlinks(to: first.id) == [source.id])

        try source.orderedBlocks[0].store(TextPayload(semantic: NSAttributedString(string: "[[Second]]")))
        try context.save()

        let updated = try #require(await builder.edges(for: source.id))
        graph.replaceOutgoing(for: source.id, with: updated.targets, unresolvedTitles: updated.unresolved)

        #expect(graph.backlinks(to: first.id).isEmpty)
        #expect(graph.backlinks(to: second.id) == [source.id])
    }

    @Test("An empty library produces an empty graph rather than failing")
    func emptyLibrary() async throws {
        let container = try VersoModelContainer.makeInMemory()
        let graph = await LinkIndexBuilder(modelContainer: container).build()
        #expect(graph == LinkGraph())
    }
}
