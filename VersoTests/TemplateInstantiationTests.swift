import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Template instantiation")
struct TemplateInstantiationTests {

    let catalog = TemplateCatalog.shared

    private func makeContext() throws -> ModelContext {
        ModelContext(try VersoModelContainer.makeInMemory())
    }

    private func decodeTemplate(_ json: String) throws -> Template {
        try JSONDecoder().decode(Template.self, from: Data(json.utf8))
    }

    // MARK: - Catalog

    @Test("Phase 1 ships blank and grocery-run, both instantiable")
    func catalogContents() {
        #expect(Set(catalog.all.map(\.id)) == ["blank", "grocery-run"])
        #expect(Set(catalog.supported.map(\.id)) == ["blank", "grocery-run"])
    }

    // MARK: - Blank

    @Test("Blank produces a single empty text block and no title")
    func blankTemplate() throws {
        let context = try makeContext()
        let note = try TemplateInstantiator.makeNote(from: catalog.blank, in: context)

        #expect(note.title.isEmpty)
        #expect(note.templateID == "blank")
        #expect(note.orderedBlocks.count == 1)
        #expect(note.orderedBlocks[0].type == .text)
        #expect(try note.orderedBlocks[0].decoded(as: TextPayload.self).plain.isEmpty)
    }

    // MARK: - Grocery run

    @Test("Grocery Run builds its blocks in order and carries its stock")
    func groceryRunStructure() throws {
        let context = try makeContext()
        let template = try #require(catalog.template(id: "grocery-run"))
        let note = try TemplateInstantiator.makeNote(
            from: template,
            in: context,
            date: Date(timeIntervalSince1970: 1_760_000_000),
            locale: Locale(identifier: "en_US")
        )

        #expect(note.orderedBlocks.map(\.type) == [.checklist, .divider, .text])
        #expect(note.orderedBlocks.map(\.position) == [0, 1, 2])
        #expect(note.stockID == "ruled")
        #expect(note.themeID == nil, "the template inherits the app theme")
        #expect(note.title.hasPrefix("Grocery Run"))
        #expect(note.title != template.titleFormat, "the date token should have been substituted")
    }

    @Test("Grocery Run's aisles arrive as ordered checklist groups")
    func groceryRunGroups() throws {
        let context = try makeContext()
        let template = try #require(catalog.template(id: "grocery-run"))
        let note = try TemplateInstantiator.makeNote(from: template, in: context)

        let checklist = try note.orderedBlocks[0].decoded(as: ChecklistPayload.self)
        #expect(checklist.groupBy == .group)
        #expect(checklist.itemFields == [.quantity, .unit, .price, .note])
        #expect(checklist.items.isEmpty)
        #expect(checklist.groups.sorted { $0.position < $1.position }.map(\.label) == [
            "Produce", "Bakery", "Dairy & Eggs", "Meat & Fish", "Pantry", "Frozen", "Household",
        ])
    }

    // MARK: - Persistence

    @Test("An instantiated note round-trips through the store")
    func instantiatedNotePersists() throws {
        let context = try makeContext()
        let template = try #require(catalog.template(id: "grocery-run"))
        let created = try TemplateInstantiator.makeNote(from: template, in: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(fetched.count == 1)

        let note = try #require(fetched.first)
        #expect(note.id == created.id)
        #expect(note.orderedBlocks.count == 3)
        #expect(note.orderedBlocks.map(\.typeRaw) == ["checklist", "divider", "text"])
    }

    @Test("Checking an item survives a save and refetch")
    func checkedItemPersists() throws {
        let context = try makeContext()
        let template = try #require(catalog.template(id: "grocery-run"))
        let note = try TemplateInstantiator.makeNote(from: template, in: context)

        let block = note.orderedBlocks[0]
        var checklist = try block.decoded(as: ChecklistPayload.self)
        checklist.items.append(.init(label: "Lemons", group: "produce"))
        let id = checklist.items[0].id
        checklist.setChecked(true, itemID: id)
        try block.store(checklist)
        try context.save()

        let refetched = try #require(try context.fetch(FetchDescriptor<Note>()).first)
        let restored = try refetched.orderedBlocks[0].decoded(as: ChecklistPayload.self)
        #expect(restored.items.count == 1)
        #expect(restored.items[0].checked)
        #expect(restored.items[0].checkedAt != nil)
    }

    // MARK: - Failure modes

    @Test("A template naming an unknown block type is rejected")
    func unknownBlockTypeIsRejected() throws {
        let template = try decodeTemplate("""
        {"kind":"template","id":"bad","name":"Bad","blocks":[{"type":"hologram","payload":{}}]}
        """)

        #expect(template.unsupportedBlockTypes() == ["hologram"])
        #expect(!template.isSupported)
        #expect(throws: TemplateError.self) {
            _ = try TemplateInstantiator.makeBlocks(from: template)
        }
    }

    @Test("A template using a block type from a later phase is hidden, not broken")
    func laterPhaseBlockTypeIsHidden() throws {
        let template = try decodeTemplate("""
        {"kind":"template","id":"future","name":"Future","blocks":[
          {"type":"heading","payload":{"level":1,"text":"Session"}},
          {"type":"callout","payload":{}}
        ]}
        """)

        #expect(template.unsupportedBlockTypes() == ["callout"])
        #expect(!template.isSupported)
        #expect(throws: TemplateError.self) {
            _ = try TemplateInstantiator.makeBlocks(from: template)
        }
    }

    @Test("A malformed payload fails without inserting a partial note")
    func malformedPayloadLeavesStoreUntouched() throws {
        let context = try makeContext()
        let template = try decodeTemplate("""
        {"kind":"template","id":"broken","name":"Broken","blocks":[
          {"type":"heading","payload":{"level":1,"text":"Fine"}},
          {"type":"heading","payload":{"level":"one"}}
        ]}
        """)

        #expect(throws: TemplateError.self) {
            _ = try TemplateInstantiator.makeNote(from: template, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Block>()).isEmpty)
    }

    // MARK: - Title tokens

    @Test("Title tokens are substituted")
    func titleTokens() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let locale = Locale(identifier: "en_US")

        let rendered = TemplateInstantiator.title(
            from: "{weekday} — {date} at {time}",
            date: date,
            locale: locale
        )

        #expect(!rendered.contains("{"))
        #expect(rendered.contains("—"))
    }

    @Test("A template with no title format leaves the title empty")
    func noTitleFormat() {
        #expect(TemplateInstantiator.title(from: nil, date: Date()).isEmpty)
    }

    // MARK: - The zero-Swift guarantee

    /// Section 2: adding a template must require one new JSON file and no Swift
    /// changes. This builds a template that exists nowhere in the source tree
    /// and instantiates it through the same path the bundled ones use.
    @Test("A template invented at runtime instantiates with no code changes")
    func newTemplateNeedsNoSwift() throws {
        let context = try makeContext()
        let template = try decodeTemplate("""
        {
          "kind": "template",
          "id": "invented-at-runtime",
          "name": "Invented",
          "systemImage": "sparkles",
          "themeID": "foxed",
          "stockID": "manuscript",
          "revealStyleID": "unfurl",
          "titleFormat": "Invented on {date}",
          "blocks": [
            { "type": "heading", "payload": { "level": 2, "text": "Section" } },
            { "type": "list", "payload": { "style": "numbered", "items": [
                { "text": "First" }, { "text": "Second" }
            ] } },
            { "type": "checklist", "payload": {
                "groupBy": "checked",
                "itemFields": ["note"],
                "items": [{ "label": "Try it" }]
            } },
            { "type": "divider", "payload": { "style": "fleuron" } }
          ]
        }
        """)

        #expect(template.isSupported)
        let note = try TemplateInstantiator.makeNote(from: template, in: context)

        #expect(note.themeID == "foxed")
        #expect(note.stockID == "manuscript")
        #expect(note.revealStyleID == "unfurl")
        #expect(note.orderedBlocks.map(\.type) == [.heading, .list, .checklist, .divider])

        #expect(try note.orderedBlocks[0].decoded(as: HeadingPayload.self).level == .two)
        #expect(try note.orderedBlocks[1].decoded(as: ListPayload.self).items.map(\.text) == ["First", "Second"])
        #expect(try note.orderedBlocks[2].decoded(as: ChecklistPayload.self).groupBy == .checked)
        #expect(try note.orderedBlocks[3].decoded(as: DividerPayload.self).style == .fleuron)
    }
}
