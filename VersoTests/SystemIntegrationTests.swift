import CoreSpotlight
import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Deep links")
struct VersoURLTests {

    @Test("A note link round-trips")
    func noteLinkRoundTrips() {
        let id = UUID()
        #expect(VersoURL.destination(for: VersoURL.note(id)) == .note(id))
    }

    @Test("The capture link is recognised")
    func captureLink() {
        #expect(VersoURL.destination(for: VersoURL.capture) == .capture)
    }

    /// A link the app does not understand must do nothing, not something.
    @Test("Foreign and malformed links resolve to nothing", arguments: [
        "https://example.com/note/abc",
        "verso://note/not-a-uuid",
        "verso://",
        "verso://somethingelse",
    ])
    func malformedLinks(raw: String) {
        guard let url = URL(string: raw) else { return }
        #expect(VersoURL.destination(for: url) == nil)
    }
}

@Suite("Handoff and Spotlight eligibility")
@MainActor
struct ActivityEligibilityTests {

    private func makeNote(locked: Bool = false, hidden: Bool = false, trashed: Bool = false) throws -> Note {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "Notes on ink")
        context.insert(note)
        let block = try Block(TextPayload(plain: "Iron gall bites into the paper."))
        context.insert(block)
        note.append(block)

        note.isLocked = locked
        note.isHidden = hidden
        note.isTrashed = trashed
        return note
    }

    @Test("An ordinary note is offered to Handoff and Spotlight")
    func ordinaryNoteIsEligible() throws {
        let activity = VersoActivity.activity(for: try makeNote())

        #expect(activity.isEligibleForHandoff)
        #expect(activity.isEligibleForSearch)
        #expect(activity.isEligibleForPrediction)
        #expect(VersoActivity.noteID(from: activity) != nil)
    }

    /// Section 7 names Spotlight first among the places a locked note must not
    /// appear, and Handoff advertises to a whole other device.
    @Test("A locked, hidden or trashed note is advertised nowhere", arguments: [
        (true, false, false),
        (false, true, false),
        (false, false, true),
    ])
    func excludedNotesAreNotAdvertised(locked: Bool, hidden: Bool, trashed: Bool) throws {
        let note = try makeNote(locked: locked, hidden: hidden, trashed: trashed)
        let activity = VersoActivity.activity(for: note)

        #expect(!activity.isEligibleForHandoff)
        #expect(!activity.isEligibleForSearch)
        #expect(!activity.isEligibleForPrediction)
        #expect(activity.persistentIdentifier == nil)
    }

    @Test("A locked note's title does not travel either")
    func lockedTitleIsRedacted() throws {
        let activity = VersoActivity.activity(for: try makeNote(locked: true))
        #expect(activity.title != "Notes on ink")
    }

    @Test("An activity of the wrong type yields no note")
    func wrongActivityType() {
        #expect(VersoActivity.noteID(from: NSUserActivity(activityType: "com.example.other")) == nil)
    }
}

@Suite("Drag and drop")
@MainActor
struct NoteTransferTests {

    private func makeNote() throws -> Note {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "Shopping")
        context.insert(note)
        let block = try Block(ChecklistPayload(items: [.init(label: "Lemons"), .init(label: "Bread")]))
        context.insert(block)
        note.append(block)
        return note
    }

    /// A note dropped into Mail should arrive as something the recipient can
    /// read, not a link that only resolves on the device it came from.
    @Test("A dragged note carries its Markdown")
    func transferCarriesMarkdown() throws {
        let transfer = NoteTransfer(note: try makeNote())

        #expect(transfer.title == "Shopping")
        #expect(transfer.markdown.contains("# Shopping"))
        #expect(transfer.markdown.contains("Lemons"))
    }

    @Test("A locked note carries nothing")
    func lockedNoteCarriesNothing() throws {
        let note = try makeNote()
        note.isLocked = true

        let transfer = NoteTransfer(note: note)
        #expect(!transfer.markdown.contains("Lemons"))
        #expect(transfer.title != "Shopping")
    }
}

@Suite("Spotlight indexing")
struct SpotlightSourceTests {

    /// The index persists outside the app, so an entry for a note that has
    /// since been locked has to be actively removed — not merely not re-added.
    @Test("Excluded notes come back as deletions, not omissions")
    func exclusionsAreDeletions() async throws {
        let container = try VersoModelContainer.makeInMemory()
        let context = ModelContext(container)

        let open = Note(title: "Open")
        let locked = Note(title: "Locked")
        locked.isLocked = true
        let hidden = Note(title: "Hidden")
        hidden.isHidden = true

        for note in [open, locked, hidden] { context.insert(note) }
        try context.save()

        let (indexable, excluded) = await SpotlightSource(modelContainer: container).entries()

        #expect(indexable.map(\.title) == ["Open"])
        #expect(excluded.count == 2)
        #expect(excluded.contains(locked.id.uuidString))
        #expect(excluded.contains(hidden.id.uuidString))
    }

    @Test("An untitled note is indexed under something findable")
    func untitledNotesAreStillFindable() async throws {
        let container = try VersoModelContainer.makeInMemory()
        let context = ModelContext(container)
        context.insert(Note())
        try context.save()

        let (indexable, _) = await SpotlightSource(modelContainer: container).entries()
        #expect(indexable.first?.title.isEmpty == false)
    }
}

@Suite("Intents")
struct IntentTests {

    /// Section 7 lists quick capture, add-to-list, start workout, search and
    /// open template. "Start workout" is the template intent with a parameter —
    /// naming a template in Swift would be the `if templateID ==` that section 2
    /// rules out.
    @Test("Every shortcut phrase is generic rather than naming a template")
    func shortcutsNameNoTemplate() {
        let templateIDs = TemplateCatalog.shared.all.map(\.id)
        for id in templateIDs {
            #expect(id != "start-workout", "no template should be special-cased")
        }
        #expect(TemplateCatalog.shared.supported.count > 1, "the template intent needs choices")
    }

    /// A template added as a JSON file has to reach Shortcuts without any Swift
    /// change — the section 2 guarantee extends to system integration.
    @Test("Shortcuts sees every supported template")
    func templateEntitiesCoverTheCatalogue() async throws {
        let entities = try await TemplateEntityQuery().suggestedEntities()
        #expect(entities.count == TemplateCatalog.shared.supported.count)
        #expect(entities.contains { $0.id == "grocery-run" })
        #expect(entities.contains { $0.id == "strength-session" })
    }

    @Test("A template entity carries what Shortcuts shows")
    func templateEntityDisplay() throws {
        let template = try #require(TemplateCatalog.shared.template(id: "grocery-run"))
        let entity = TemplateEntity(template)

        #expect(entity.id == "grocery-run")
        #expect(entity.name == "Grocery Run")
        #expect(entity.summary != nil)
    }

    /// An intent is one more way a note can leave the app.
    @Test("A locked note is opaque to intents")
    @MainActor
    func lockedNotesAreOpaqueToIntents() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "Diary")
        context.insert(note)
        let block = try Block(TextPayload(plain: "something personal"))
        context.insert(block)
        note.append(block)
        note.isLocked = true

        let entity = NoteEntity(note)
        #expect(entity.title != "Diary")
        #expect(entity.summary.isEmpty)
    }
}
