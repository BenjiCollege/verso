import Foundation
import OSLog
import SwiftData

/// Who links to whom.
///
/// Held in memory rather than persisted. Links live inside archived text, which
/// SwiftData cannot form a predicate against, so the alternatives were a new
/// `@Model` — a schema change, and schema changes are yours to approve — or an
/// index built by reading the archives once. This is the second.
///
/// The cost is a background pass proportional to the number of text blocks.
/// It runs on first use rather than at launch, so it never touches the 400ms
/// cold-launch budget, and every later edit patches the graph incrementally.
struct LinkGraph: Sendable, Equatable {
    /// Source note → notes it links to.
    var outgoing: [UUID: Set<UUID>] = [:]
    /// Target note → notes that link to it.
    var incoming: [UUID: Set<UUID>] = [:]
    /// Link titles that matched no note, per source. These are the offer to
    /// create a note, not an error.
    var unresolved: [UUID: Set<String>] = [:]

    func backlinks(to noteID: UUID) -> Set<UUID> {
        incoming[noteID] ?? []
    }

    func links(from noteID: UUID) -> Set<UUID> {
        outgoing[noteID] ?? []
    }

    /// Replaces one note's outgoing edges and repairs the reverse map.
    mutating func replaceOutgoing(for source: UUID, with targets: Set<UUID>, unresolvedTitles: Set<String>) {
        for previous in outgoing[source] ?? [] where !targets.contains(previous) {
            incoming[previous]?.remove(source)
            if incoming[previous]?.isEmpty == true { incoming[previous] = nil }
        }
        for target in targets {
            incoming[target, default: []].insert(source)
        }
        outgoing[source] = targets.isEmpty ? nil : targets
        unresolved[source] = unresolvedTitles.isEmpty ? nil : unresolvedTitles
    }

    mutating func remove(note: UUID) {
        replaceOutgoing(for: note, with: [], unresolvedTitles: [])
        outgoing[note] = nil
        unresolved[note] = nil

        // And as a target, which `replaceOutgoing` cannot reach: it repairs the
        // edges out of this note, not the ones into it. Left alone, every note
        // that pointed here would keep an edge to something deleted, and
        // `incoming[note]` would hold a dead id for the life of the process.
        for source in incoming[note] ?? [] {
            outgoing[source]?.remove(note)
            if outgoing[source]?.isEmpty == true { outgoing[source] = nil }
        }
        incoming[note] = nil
    }
}

/// Reads the store off the main actor.
///
/// `@ModelActor` gives this its own `ModelContext`, which is what makes it safe
/// to decode thousands of archives without blocking a scroll. Nothing crosses
/// the boundary except `LinkGraph`, which is `Sendable`.
@ModelActor
actor LinkIndexBuilder {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "links")

    /// Titles are matched case- and whitespace-insensitively. First note wins a
    /// duplicate title, deterministically by id.
    ///
    /// Deliberately recomputed on every call rather than cached. Caching it
    /// looks like an easy win — `edges(for:)` re-reads the whole library to
    /// patch one note — but it is the wrong trade twice over: `noteDidChange`
    /// fires once per editor dismiss, not per keystroke, so there is little to
    /// win; and a cache would have to *remove* a renamed note's old title as
    /// well as add its new one, or a `[[Old Title]]` elsewhere keeps resolving
    /// to a note that is no longer called that. Correct beats clever on a cold
    /// path.
    private static func titleMap(of notes: [Note]) -> [String: UUID] {
        var byTitle: [String: UUID] = [:]
        for note in notes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let key = titleKey(note.title)
            guard !key.isEmpty, byTitle[key] == nil else { continue }
            byTitle[key] = note.id
        }
        return byTitle
    }

    func build() -> LinkGraph {
        var graph = LinkGraph()

        let notes: [Note]
        do {
            notes = try modelContext.fetch(FetchDescriptor<Note>())
        } catch {
            Self.logger.error("Link index build failed: \(error.localizedDescription, privacy: .public)")
            return graph
        }

        let byTitle = Self.titleMap(of: notes)

        for note in notes {
            let (targets, unresolved) = Self.edges(from: note, titles: byTitle)
            graph.replaceOutgoing(for: note.id, with: targets, unresolvedTitles: unresolved)
        }
        return graph
    }

    /// Recomputes a single note's edges. Used after an edit, so a keystroke
    /// never triggers a full rebuild.
    func edges(for noteID: UUID) -> (targets: Set<UUID>, unresolved: Set<String>)? {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == noteID })
        guard let note = try? modelContext.fetch(descriptor).first else { return nil }

        let all = (try? modelContext.fetch(FetchDescriptor<Note>())) ?? []
        return Self.edges(from: note, titles: Self.titleMap(of: all))
    }

    // MARK: - Extraction

    static func titleKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Two sources of truth, in order: the `noteLink` attribute, which survives
    /// the target being renamed, then the bracketed title, which is what a
    /// hand-typed link has.
    private static func edges(from note: Note, titles: [String: UUID]) -> (Set<UUID>, Set<String>) {
        var targets: Set<UUID> = []
        var unresolved: Set<String> = []

        for block in note.orderedBlocks where block.type == .text {
            guard let payload = try? block.decoded(as: TextPayload.self) else { continue }

            // Read the archive directly. Going via `AttributedString` would
            // silently drop `versoNoteLink`, because custom keys outside a
            // known AttributeScope do not survive that conversion.
            let attributed = payload.attributedNS
            let full = NSRange(location: 0, length: attributed.length)
            attributed.enumerateAttribute(VersoTextAttribute.noteLink, in: full) { value, _, _ in
                if let id = (value as? String).flatMap(UUID.init(uuidString:)) {
                    targets.insert(id)
                }
            }

            for title in WikiLink.titles(in: payload.plain) {
                if let id = titles[titleKey(title)] {
                    targets.insert(id)
                } else {
                    unresolved.insert(title)
                }
            }
        }

        targets.remove(note.id)
        return (targets, unresolved)
    }
}

/// The main-actor face of the index.
@MainActor
@Observable
final class LinkIndex {

    private(set) var graph = LinkGraph()
    private(set) var isBuilding = false
    private var hasBuilt = false

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// Builds once, lazily. Safe to call from `.task` on every view that needs
    /// backlinks — repeat calls are free.
    func buildIfNeeded() async {
        guard !hasBuilt, !isBuilding else { return }
        isBuilding = true
        defer { isBuilding = false }

        let builder = LinkIndexBuilder(modelContainer: container)
        graph = await builder.build()
        hasBuilt = true
    }

    func rebuild() async {
        hasBuilt = false
        await buildIfNeeded()
    }

    /// Patches one note's edges after an edit.
    func noteDidChange(_ noteID: UUID) async {
        guard hasBuilt else { return }
        let builder = LinkIndexBuilder(modelContainer: container)
        guard let (targets, unresolved) = await builder.edges(for: noteID) else {
            graph.remove(note: noteID)
            return
        }
        graph.replaceOutgoing(for: noteID, with: targets, unresolvedTitles: unresolved)
    }

    func backlinks(to noteID: UUID) -> Set<UUID> {
        graph.backlinks(to: noteID)
    }
}
