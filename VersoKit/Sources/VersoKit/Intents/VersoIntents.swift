import AppIntents
import Foundation
import SwiftData

/// Everything Verso can be asked to do from outside itself.
///
/// SiriKit is deprecated, so this is the whole surface: Siri, Shortcuts, the
/// Action Button, Control Centre, the Lock Screen and widget buttons all arrive
/// through App Intents.

// MARK: - Capture

/// Quick capture. The one that has to work from a cold start with the phone
/// locked, so it does the least possible: write the note, return.
struct QuickCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Capture"
    static let description = IntentDescription(
        "Writes a new note straight away, without opening Verso.",
        categoryName: "Capture"
    )

    /// Deliberately false: the point of quick capture is that it does not make
    /// you wait for an app to launch.
    static let openAppWhenRun = false

    @Parameter(title: "Text", requestValueDialog: "What would you like to note?")
    var text: String

    /// Structures the text the way pasting does — a list stays a list.
    @Parameter(title: "Find structure", default: true)
    var findStructure: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text)") {
            \.$findStructure
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> & ProvidesDialog {
        let context = ModelContext(VersoIntentContainer.shared)

        let note: Note
        if findStructure {
            note = try await IntentIntelligence.shared.makeNote(from: text, in: context)
        } else {
            note = try TemplateInstantiator.makeNote(from: TemplateCatalog.shared.blank, in: context)
            note.title = HeuristicIntelligence.truncate(
                HeuristicIntelligence.firstSentence(of: text),
                toWords: 8
            )
            if let block = note.orderedBlocks.first {
                try block.store(TextPayload(plain: text))
            }
        }

        try context.save()
        let entity = NoteEntity(note)
        return .result(value: entity, dialog: IntentDialog("Saved to Verso."))
    }
}

/// Adding to a list without opening the app — the reason a shopping list on a
/// phone beats one on paper.
struct AddToListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to a List"
    static let description = IntentDescription(
        "Adds an item to a checklist in one of your notes.",
        categoryName: "Capture"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Item", requestValueDialog: "What should I add?")
    var item: String

    @Parameter(title: "Note")
    var note: NoteEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$item) to \(\.$note)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let source = IntentDataSource(modelContainer: VersoIntentContainer.shared)
        let added = await source.appendItem(item, toNoteNamed: note?.title)

        guard added else {
            return .result(dialog: IntentDialog("I couldn't find a list to add that to."))
        }
        return .result(dialog: IntentDialog("Added \(item)."))
    }
}

// MARK: - Templates

/// Creating a note from a template.
///
/// One intent covers section 7's "open template" *and* "start workout": the
/// template is a parameter, so a Shortcut named "Start workout" is one the user
/// builds by choosing a template, and Verso has no idea which one is a workout.
/// Naming a specific template here would be the `if templateID ==` that section
/// 2 forbids, wearing an Intent's clothes.
struct NewNoteFromTemplateIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note from Template"
    static let description = IntentDescription(
        "Creates a note from one of your templates and opens it.",
        categoryName: "Capture"
    )
    static let openAppWhenRun = true

    @Parameter(title: "Template")
    var template: TemplateEntity

    static var parameterSummary: some ParameterSummary {
        Summary("New \(\.$template) note")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> & OpensIntent {
        guard let found = TemplateCatalog.shared.template(id: template.id) else {
            throw VersoIntentError.templateMissing
        }

        let context = ModelContext(VersoIntentContainer.shared)
        let note = try TemplateInstantiator.makeNote(from: found, in: context)
        try context.save()

        return .result(value: NoteEntity(note), opensIntent: OpenNoteIntent(note: NoteEntity(note)))
    }
}

// MARK: - Finding and opening

struct SearchNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Notes"
    static let description = IntentDescription(
        "Finds notes matching what you're looking for.",
        categoryName: "Find"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Search for", requestValueDialog: "What are you looking for?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search Verso for \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[NoteEntity]> {
        let source = IntentDataSource(modelContainer: VersoIntentContainer.shared)
        return .result(value: await source.notes(matching: query).map(NoteEntity.init))
    }
}

/// Opening a specific note. Also what Spotlight and Handoff resolve to.
struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Note"
    static let description = IntentDescription("Opens a note in Verso.", categoryName: "Find")
    static let openAppWhenRun = true

    @Parameter(title: "Note")
    var note: NoteEntity

    init() {}

    init(note: NoteEntity) {
        self.note = note
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationRequest.shared.openNote(id: note.id)
        return .result()
    }
}

/// Starting a recording from outside the app — the Action Button case, where
/// getting the microphone running matters more than what you are looking at.
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Record a Note"
    static let description = IntentDescription(
        "Opens Verso with a new note and starts recording.",
        categoryName: "Capture"
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContext(VersoIntentContainer.shared)
        let note = try TemplateInstantiator.makeNote(from: TemplateCatalog.shared.blank, in: context)
        try context.save()

        NavigationRequest.shared.openNote(id: note.id, startRecording: true)
        return .result()
    }
}

// MARK: - Shortcuts

/// The phrases offered without the user building anything.
///
/// Kept short and generic. A phrase naming a specific template would bake a
/// template id into the app, which is the thing section 2 rules out.
struct VersoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickCaptureIntent(),
            phrases: [
                "Note in \(.applicationName)",
                "Capture in \(.applicationName)",
                "Add a note to \(.applicationName)",
            ],
            shortTitle: "Quick Capture",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AddToListIntent(),
            phrases: [
                "Add to my \(.applicationName) list",
                "Add an item in \(.applicationName)",
            ],
            shortTitle: "Add to a List",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: NewNoteFromTemplateIntent(),
            phrases: [
                "New \(.applicationName) note from a template",
                "Start a \(.applicationName) template",
            ],
            shortTitle: "From a Template",
            systemImageName: "doc.on.doc"
        )
        AppShortcut(
            intent: SearchNotesIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Find a note in \(.applicationName)",
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Record a note in \(.applicationName)",
                "Start recording in \(.applicationName)",
            ],
            shortTitle: "Record",
            systemImageName: "mic"
        )
    }
}

enum VersoIntentError: LocalizedError {
    case templateMissing

    var errorDescription: String? {
        switch self {
        case .templateMissing: String(localized: "That template no longer exists.")
        }
    }
}

/// The intelligence provider intents use.
///
/// Intents run outside the app, so they cannot borrow its `IntelligenceService`.
/// The heuristic provider is used unconditionally here: quick capture has to
/// finish before the phone locks again, and waiting on a language model is not
/// worth the structure it might add.
@MainActor
enum IntentIntelligence {
    static let shared = IntelligenceService(provider: HeuristicIntelligence(), availability: .frameworkUnavailable)
}
