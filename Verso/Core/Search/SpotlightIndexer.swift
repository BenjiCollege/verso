import CoreSpotlight
import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// Putting notes in Spotlight, and keeping them out of it.
///
/// Section 7 names `CSSearchableIndex` first among the places a locked or
/// hidden note must not appear, and it is the one that persists outside the
/// app — an index entry survives the note being locked unless something goes
/// and removes it. So this both adds and deletes, every time.
@MainActor
@Observable
final class SpotlightIndexer {

    static let logger = Logger(subsystem: "com.verso.notes", category: "spotlight")
    static let domain = "com.verso.notes.notes"

    private(set) var lastIndexed: Date?

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// Rebuilds the index from the library.
    ///
    /// Deleting the domain first is deliberate: incremental updates drift, and
    /// a stale entry for a note that has since been locked is a leak, not an
    /// inconvenience.
    func reindex() async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        let source = SpotlightSource(modelContainer: container)
        let (indexable, excluded) = await source.entries()

        let index = CSSearchableIndex.default()
        do {
            if !excluded.isEmpty {
                try await index.deleteSearchableItems(withIdentifiers: excluded)
            }

            let items = indexable.map { entry -> CSSearchableItem in
                let attributes = CSSearchableItemAttributeSet(contentType: .text)
                attributes.title = entry.title
                attributes.contentDescription = entry.summary
                attributes.contentModificationDate = entry.modifiedAt
                attributes.keywords = entry.keywords

                let item = CSSearchableItem(
                    uniqueIdentifier: entry.id.uuidString,
                    domainIdentifier: Self.domain,
                    attributeSet: attributes
                )
                // Entries expire rather than lingering forever if the app is
                // never opened again.
                item.expirationDate = .distantFuture
                return item
            }

            try await index.indexSearchableItems(items)
            lastIndexed = Date()
        } catch {
            Self.logger.error("Spotlight update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called when a note is locked, hidden or deleted, so its entry goes
    /// immediately rather than at the next rebuild.
    func remove(noteID: UUID) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        try? await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [noteID.uuidString])
    }

    func removeEverything() async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        try? await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domain])
    }
}

@ModelActor
actor SpotlightSource {

    struct Entry: Sendable {
        var id: UUID
        var title: String
        var summary: String
        var keywords: [String]
        var modifiedAt: Date
    }

    /// Returns what belongs in the index and what has to be taken out of it.
    func entries() -> (indexable: [Entry], excluded: [String]) {
        let notes = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []

        var indexable: [Entry] = []
        var excluded: [String] = []

        for note in notes {
            guard VaultPolicy.isEligibleForIndexing(note) else {
                excluded.append(note.id.uuidString)
                continue
            }

            let body = note.orderedBlocks
                .map { BlockRegistry.shared.plainText(for: $0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            indexable.append(
                Entry(
                    id: note.id,
                    title: note.title.isEmpty ? String(localized: "Untitled") : note.title,
                    summary: String(body.prefix(400)),
                    keywords: (note.tags ?? []).map(\.name),
                    modifiedAt: note.modifiedAt
                )
            )
        }
        return (indexable, excluded)
    }
}
