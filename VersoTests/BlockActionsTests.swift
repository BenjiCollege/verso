import Foundation
import SwiftData
import Testing
@testable import VersoKit

/// Deleting a block is offered through a long press, which people trigger by
/// accident. So the test that matters is not that delete works — it is that the
/// block comes back whole, in the right place, under its own id.
@Suite("Block actions")
@MainActor
struct BlockActionsTests {

    private func makeNote(in context: ModelContext) throws -> Note {
        let note = Note(title: "Page")
        context.insert(note)
        for text in ["one", "two", "three"] {
            let block = try Block(TextPayload(plain: text))
            context.insert(block)
            note.append(block)
        }
        return note
    }

    private func texts(of note: Note) throws -> [String] {
        try note.orderedBlocks.map { try $0.decoded(as: TextPayload.self).plain }
    }

    @Test("Duplicating puts the copy directly after the original")
    func duplicateInsertsAfter() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)
        let actions = BlockActions()

        let second = note.orderedBlocks[1]
        actions.duplicate(second, in: note, context: context)

        #expect(try texts(of: note) == ["one", "two", "two", "three"])
        #expect(note.orderedBlocks.map(\.position) == [0, 1, 2, 3])
        #expect(note.orderedBlocks[1].id != note.orderedBlocks[2].id, "a copy, not the same block twice")
    }

    @Test("Deleting removes it and offers it back")
    func deleteOffersRecovery() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)
        let actions = BlockActions()

        actions.delete(note.orderedBlocks[1], in: note, context: context)

        #expect(try texts(of: note) == ["one", "three"])
        #expect(note.orderedBlocks.map(\.position) == [0, 1], "positions close up")
        #expect(actions.recovered != nil)
    }

    @Test("Undo puts it back where it was, under its own id")
    func undoRestoresInPlace() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)
        let actions = BlockActions()

        let doomed = note.orderedBlocks[1]
        let id = doomed.id
        actions.delete(doomed, in: note, context: context)
        actions.undo(in: note, context: context)

        #expect(try texts(of: note) == ["one", "two", "three"])
        #expect(note.orderedBlocks.map(\.position) == [0, 1, 2])
        // The id matters: a link, a sync mark or a version delta that referred
        // to this block still refers to it.
        #expect(note.orderedBlocks[1].id == id)
        #expect(actions.recovered == nil, "the offer is spent")
    }

    @Test("Deleting the last block still recovers")
    func undoRestoresAtTheEnd() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)
        let actions = BlockActions()

        actions.delete(note.orderedBlocks[2], in: note, context: context)
        actions.undo(in: note, context: context)

        #expect(try texts(of: note) == ["one", "two", "three"])
    }

    @Test("An offer from another note is not honoured here")
    func undoIsScopedToItsNote() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)
        let other = try makeNote(in: context)
        let actions = BlockActions()

        actions.delete(note.orderedBlocks[0], in: note, context: context)
        actions.undo(in: other, context: context)

        #expect(try texts(of: other) == ["one", "two", "three"], "nothing added")
        #expect(try texts(of: note) == ["two", "three"], "and nothing restored")
    }

    @Test("Dismissing withdraws the offer without restoring")
    func dismissDropsIt() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)
        let actions = BlockActions()

        actions.delete(note.orderedBlocks[0], in: note, context: context)
        actions.dismiss()

        #expect(actions.recovered == nil)
        #expect(try texts(of: note) == ["two", "three"])
    }
}
