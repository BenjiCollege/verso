import Foundation
import SwiftData

extension Folder {
    /// Case-insensitive dedupe, the same contract `Tag.findOrCreate` keeps.
    ///
    /// Folders have no unique constraint either — CloudKit forbids one — so two
    /// devices can both make "Work" before sync converges. Matching on a folded
    /// name at the point of creation is what stops one device's typing from
    /// producing a second folder on the other.
    static func findOrCreate(named name: String, in context: ModelContext) throws -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.lowercased()
        let existing = try context.fetch(FetchDescriptor<Folder>())

        if let match = existing.first(where: { $0.name.lowercased() == folded }) {
            return match
        }
        let folder = Folder(
            name: trimmed,
            position: (existing.map(\.position).max() ?? -1) + 1
        )
        context.insert(folder)
        return folder
    }

    /// Notes still in this folder and not in the bin.
    ///
    /// The relationship holds trashed notes too — deleting a note does not
    /// unfile it, so that restoring puts it back where it was — which makes the
    /// raw count wrong for anything a reader sees.
    var visibleNotes: [Note] {
        (notes ?? []).filter { !$0.isTrashed && !$0.isHidden }
    }
}

// MARK: - Filtering the library

/// What the library is showing.
///
/// Deliberately not a `@Query` predicate. Folder and tag membership are
/// to-many relationships, which `#Predicate` cannot express against a fetched
/// set without a subquery per note, and the library has already loaded these
/// notes to draw them.
enum LibraryFilter: Hashable, Sendable {
    case all
    case folder(UUID)
    case tag(UUID)
    /// Everything filed nowhere. The pile that needs attention, and the reason
    /// filing is worth doing at all.
    case unfiled

    func matches(_ note: Note) -> Bool {
        switch self {
        case .all:
            true
        case .folder(let id):
            note.folder?.id == id
        case .tag(let id):
            (note.tags ?? []).contains { $0.id == id }
        case .unfiled:
            note.folder == nil && (note.tags ?? []).isEmpty
        }
    }
}
