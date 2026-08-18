import Foundation
import SwiftData
import Testing
@testable import VersoKit

private typealias Tag = VersoKit.Tag

/// `Folder` shipped in the schema from the start and no view ever referenced
/// it: you could not make one, see one, or put a note in one. Tags were half
/// there — the model could dedupe them, nothing could add one.
@Suite("Folders and tags")
struct OrganisationTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try VersoModelContainer.makeInMemory())
    }

    // MARK: - Folders

    @Test("findOrCreate is case-insensitive, like tags")
    func folderDedupe() throws {
        let context = try makeContext()
        let first = try Folder.findOrCreate(named: "Work", in: context)
        let second = try Folder.findOrCreate(named: "  work ", in: context)

        #expect(first.id == second.id)
        #expect(try context.fetchCount(FetchDescriptor<Folder>()) == 1)
        #expect(first.name == "Work", "the first spelling wins")
    }

    @Test("A new folder goes after the ones already there")
    func folderPositions() throws {
        let context = try makeContext()
        let a = try Folder.findOrCreate(named: "A", in: context)
        let b = try Folder.findOrCreate(named: "B", in: context)
        #expect(b.position > a.position)
    }

    /// Deleting a note does not unfile it — that is what lets restoring put it
    /// back where it was — so the raw relationship count is wrong for anything
    /// a reader sees.
    @Test("A folder's visible count excludes trashed and hidden notes")
    func visibleNotesExcludesTrash() throws {
        let context = try makeContext()
        let folder = try Folder.findOrCreate(named: "Work", in: context)

        let kept = Note(title: "Kept")
        let binned = Note(title: "Binned")
        let hidden = Note(title: "Hidden")
        for note in [kept, binned, hidden] {
            context.insert(note)
            note.folder = folder
        }
        binned.isTrashed = true
        hidden.isHidden = true

        #expect(folder.notes?.count == 3)
        #expect(folder.visibleNotes.count == 1)
    }

    // MARK: - Filtering

    @Test("Each filter matches what it says")
    func filtersMatch() throws {
        let context = try makeContext()
        let folder = try Folder.findOrCreate(named: "Work", in: context)
        let tag = try Tag.findOrCreate(named: "urgent", in: context)

        let filed = Note(title: "Filed")
        let tagged = Note(title: "Tagged")
        let loose = Note(title: "Loose")
        for note in [filed, tagged, loose] { context.insert(note) }
        filed.folder = folder
        tagged.tags = [tag]

        #expect(LibraryFilter.all.matches(loose))
        #expect(LibraryFilter.folder(folder.id).matches(filed))
        #expect(!LibraryFilter.folder(folder.id).matches(tagged))
        #expect(LibraryFilter.tag(tag.id).matches(tagged))
        #expect(!LibraryFilter.tag(tag.id).matches(filed))

        // Unfiled means neither, not either — a tagged note is filed.
        #expect(LibraryFilter.unfiled.matches(loose))
        #expect(!LibraryFilter.unfiled.matches(filed))
        #expect(!LibraryFilter.unfiled.matches(tagged))
    }

    @Test("A filter for a folder that has gone matches nothing rather than everything")
    func staleFilterIsEmpty() throws {
        let context = try makeContext()
        let note = Note(title: "Loose")
        context.insert(note)

        #expect(!LibraryFilter.folder(UUID()).matches(note))
        #expect(!LibraryFilter.tag(UUID()).matches(note))
    }

    // MARK: - Tags on a note

    @Test("A tag reaches a note and can be taken off again")
    func tagsAttachAndDetach() throws {
        let context = try makeContext()
        let note = Note(title: "Reading")
        context.insert(note)

        let tag = try Tag.findOrCreate(named: "books", in: context)
        note.tags = [tag]
        #expect(LibraryFilter.tag(tag.id).matches(note))

        note.tags = (note.tags ?? []).filter { $0.id != tag.id }
        #expect(!LibraryFilter.tag(tag.id).matches(note))
        // The tag itself survives being taken off one note.
        #expect(try context.fetchCount(FetchDescriptor<Tag>()) == 1)
    }

    @Test("A duplicated note keeps its filing")
    func duplicateKeepsFiling() throws {
        let context = try makeContext()
        let folder = try Folder.findOrCreate(named: "Work", in: context)
        let tag = try Tag.findOrCreate(named: "urgent", in: context)

        let note = Note(title: "Brief")
        context.insert(note)
        note.folder = folder
        note.tags = [tag]

        let copy = note.duplicated(into: context, titleSuffix: "Copy")
        #expect(copy.folder?.id == folder.id)
        #expect(copy.tags?.first?.id == tag.id)
    }
}
