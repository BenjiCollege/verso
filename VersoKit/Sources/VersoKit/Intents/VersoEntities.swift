import AppIntents
import Foundation
import SwiftData

/// A note, as Shortcuts and Siri see it.
struct NoteEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Note"),
        numericFormat: LocalizedStringResource("\(placeholder: .int) notes")
    )

    static let defaultQuery = NoteEntityQuery()

    var id: UUID
    var title: String
    var summary: String
    var modifiedAt: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title.isEmpty ? String(localized: "Untitled") : title),
            subtitle: summary.isEmpty ? nil : LocalizedStringResource(stringLiteral: summary)
        )
    }

    @MainActor
    init(_ note: Note) {
        self.id = note.id
        // Routed through `VaultPolicy`, so a locked note is as opaque to Siri
        // and Shortcuts as it is to the library list.
        self.title = VaultPolicy.listTitle(for: note)
        self.summary = VaultPolicy.listPreview(for: note)
        self.modifiedAt = note.modifiedAt
    }
}

/// Reads notes for the intent system, off the main actor.
@ModelActor
actor IntentDataSource {

    func notes(matching query: String? = nil, limit: Int = 30) -> [NoteEntity.Snapshot] {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { !$0.isTrashed && !$0.isHidden },
            sortBy: [SortDescriptor(\Note.modifiedAt, order: .reverse)]
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []

        let entries = notes
            // Section 7's exclusions apply here too: an intent is one more way
            // a note can leave the app.
            .filter { VaultPolicy.isEligibleForIndexing($0) }
            .map { note in
                NoteEntity.Snapshot(
                    id: note.id,
                    title: note.title,
                    summary: VaultPolicy.listPreview(for: note),
                    modifiedAt: note.modifiedAt
                )
            }

        guard let query, !query.isEmpty else { return Array(entries.prefix(limit)) }

        let index = SemanticIndex()
        let searchable = entries.map {
            SemanticIndex.Entry(noteID: $0.id, title: $0.title, text: $0.summary, isLocked: false)
        }
        let hits = index.search(query, in: searchable, limit: limit)
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return hits.compactMap { byID[$0.noteID] }
    }

    func notes(ids: [UUID]) -> [NoteEntity.Snapshot] {
        notes(limit: .max).filter { ids.contains($0.id) }
    }

    /// Finds the checklist an item should go into: the last one in the note
    /// named, or the most recently edited note that has one.
    func appendItem(_ label: String, toNoteNamed name: String?) -> Bool {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { !$0.isTrashed && !$0.isHidden },
            sortBy: [SortDescriptor(\Note.modifiedAt, order: .reverse)]
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []

        let candidates = notes.filter { note in
            guard VaultPolicy.isEligibleForIndexing(note) else { return false }
            guard let name, !name.isEmpty else { return true }
            return note.title.localizedCaseInsensitiveContains(name)
        }

        for note in candidates {
            guard let block = note.orderedBlocks.last(where: { $0.type == .checklist }),
                  var payload = try? block.decoded(as: ChecklistPayload.self)
            else { continue }

            payload.items.append(.init(label: label))
            try? block.store(payload)
            note.touch()
            try? modelContext.save()
            return true
        }
        return false
    }
}

extension NoteEntity {
    /// A `Sendable` copy, because `Note` is confined to its context and an
    /// intent runs wherever the system feels like running it.
    struct Snapshot: Sendable, Identifiable, Hashable {
        var id: UUID
        var title: String
        var summary: String
        var modifiedAt: Date
    }

    init(_ snapshot: Snapshot) {
        self.id = snapshot.id
        self.title = snapshot.title
        self.summary = snapshot.summary
        self.modifiedAt = snapshot.modifiedAt
    }
}

struct NoteEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        let source = IntentDataSource(modelContainer: VersoIntentContainer.shared)
        return await source.notes(ids: identifiers).map(NoteEntity.init)
    }

    func suggestedEntities() async throws -> [NoteEntity] {
        let source = IntentDataSource(modelContainer: VersoIntentContainer.shared)
        return await source.notes(limit: 12).map(NoteEntity.init)
    }
}

extension NoteEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [NoteEntity] {
        let source = IntentDataSource(modelContainer: VersoIntentContainer.shared)
        return await source.notes(matching: string).map(NoteEntity.init)
    }
}

/// A template, as Shortcuts sees it.
///
/// Backed by the same JSON catalogue as everything else, so a template added as
/// a file appears in Shortcuts without a line of Swift — the guarantee from
/// section 2 extends to the system integration.
struct TemplateEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Template"),
        numericFormat: LocalizedStringResource("\(placeholder: .int) templates")
    )

    static let defaultQuery = TemplateEntityQuery()

    var id: String
    var name: String
    var summary: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: summary.map { LocalizedStringResource(stringLiteral: $0) }
        )
    }

    init(_ template: Template) {
        self.id = template.id
        self.name = template.name
        self.summary = template.summary
    }
}

struct TemplateEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TemplateEntity] {
        TemplateCatalog.shared.supported
            .filter { identifiers.contains($0.id) }
            .map(TemplateEntity.init)
    }

    func suggestedEntities() async throws -> [TemplateEntity] {
        TemplateCatalog.shared.supported.map(TemplateEntity.init)
    }
}

extension TemplateEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [TemplateEntity] {
        TemplateCatalog.shared.supported
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(TemplateEntity.init)
    }
}

/// Synchronous store reads, for widget timeline providers.
///
/// `TimelineProvider`'s callbacks are completion-based and its completion
/// closures are not `Sendable`, so hopping to `IntentDataSource` to fetch would
/// mean passing a non-sending closure across an isolation boundary — which
/// Swift 6 refuses, correctly.
///
/// A widget's read is small, local and one-shot, so doing it on the calling
/// thread is both simpler and faster than arranging a hop. `ModelContext` is
/// created and used here and never escapes.
enum WidgetDataSource {

    static func recentNotes(limit: Int) -> [NoteEntity.Snapshot] {
        let context = ModelContext(VersoIntentContainer.shared)
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { !$0.isTrashed && !$0.isHidden },
            sortBy: [SortDescriptor(\Note.modifiedAt, order: .reverse)]
        )

        let notes = (try? context.fetch(descriptor)) ?? []
        return notes
            // A widget is on the Home Screen and the Lock Screen. Section 7's
            // exclusions matter more here than anywhere.
            .filter { VaultPolicy.isEligibleForIndexing($0) }
            .prefix(limit)
            .map { note in
                NoteEntity.Snapshot(
                    id: note.id,
                    title: note.title,
                    summary: VaultPolicy.listPreview(for: note),
                    modifiedAt: note.modifiedAt
                )
            }
    }
}

/// The container intents and widgets use.
///
/// Both run outside the app process, so they cannot borrow the app's. It is an
/// app-group store for the same reason.
enum VersoIntentContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: VersoModelContainer.schema,
                configurations: [VersoModelContainer.sharedConfiguration]
            )
        } catch {
            // An intent that cannot reach the store should do nothing rather
            // than take the system extension down with it.
            return (try? ModelContainer(
                for: VersoModelContainer.schema,
                configurations: [VersoModelContainer.inMemoryConfiguration]
            )) ?? {
                fatalError("No container available for intents")
            }()
        }
    }()
}
