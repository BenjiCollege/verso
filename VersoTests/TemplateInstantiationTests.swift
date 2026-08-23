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

    /// Named rather than counted: `TemplateLibraryTests` owns the count, and
    /// two tests asserting the same number means neither can be trusted to
    /// still mean anything once the library grows.
    @Test("The catalog holds blank and grocery-run, and only real templates")
    func catalogContents() {
        #expect(catalog.all.contains { $0.id == "blank" })
        #expect(catalog.all.contains { $0.id == "grocery-run" })
        #expect(Set(catalog.supported.map(\.id)) == Set(catalog.all.map(\.id)))

        // Stocks and themes are JSON in the same bundle, and a resource-rule
        // slip once loaded them here as templates that decoded to nothing.
        #expect(!catalog.all.contains { $0.id == "dot-grid" || $0.id == "manuscript" })
        #expect(catalog.all.allSatisfy { !$0.blocks.isEmpty || $0.id == "blank" })
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

        #expect(note.orderedBlocks.map(\.type) == [
            .place, .checklist, .divider, .formula, .formula, .formula,
        ])
        #expect(note.orderedBlocks.map(\.position) == [0, 1, 2, 3, 4, 5])
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

        // Found by type rather than by index: which position the list sits at
        // is the template's business, and it has moved once already.
        let block = try #require(note.orderedBlocks.first { $0.type == .checklist })
        let checklist = try block.decoded(as: ChecklistPayload.self)
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
        #expect(note.orderedBlocks.count == template.blocks.count)
        #expect(note.orderedBlocks.map(\.typeRaw) == template.blocks.map(\.type))
    }

    @Test("Checking an item survives a save and refetch")
    func checkedItemPersists() throws {
        let context = try makeContext()
        let template = try #require(catalog.template(id: "grocery-run"))
        let note = try TemplateInstantiator.makeNote(from: template, in: context)

        let block = try #require(note.orderedBlocks.first { $0.type == .checklist })
        var checklist = try block.decoded(as: ChecklistPayload.self)
        checklist.items.append(.init(label: "Lemons", group: "produce"))
        let id = checklist.items[0].id
        checklist.setChecked(true, itemID: id)
        try block.store(checklist)
        try context.save()

        let refetched = try #require(try context.fetch(FetchDescriptor<Note>()).first)
        let restoredBlock = try #require(refetched.orderedBlocks.first { $0.type == .checklist })
        let restored = try restoredBlock.decoded(as: ChecklistPayload.self)
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

    // MARK: - Dating

    /// A note made from a template is stamped with the moment it was made, and
    /// its title agrees with that stamp.
    ///
    /// Both halves matter and they are separate mechanisms: `Note.init` copies
    /// the date into `createdAt` *and* `modifiedAt`, while the title comes from
    /// substituting tokens into `titleFormat`. Nothing previously asserted they
    /// were handed the same value, so a note could have been filed under one
    /// date and named after another.
    @Test("A note is stamped with the moment it was made")
    func noteIsDatedAtCreation() throws {
        let context = try makeContext()
        let when = Date(timeIntervalSince1970: 1_760_000_000)

        let template = Template(
            id: "dating",
            name: "Dating",
            titleFormat: "Log — {date} {time}",
            blocks: [Template.BlockSpec(type: "text", payload: .object([:]))]
        )

        let note = try TemplateInstantiator.makeNote(from: template, in: context, date: when)

        #expect(note.createdAt == when)
        #expect(note.modifiedAt == when)
        #expect(note.title == TemplateInstantiator.title(from: template.titleFormat, date: when))
        #expect(!note.title.contains("{"))
    }

    /// The default is *now*, not a fixed date — the parameter exists so tests can
    /// pin it, and a caller that omits it must get the current moment.
    @Test("Omitting the date means now")
    func defaultDateIsNow() throws {
        let context = try makeContext()
        let before = Date()

        let template = Template(
            id: "dating-default",
            name: "Dating",
            blocks: [Template.BlockSpec(type: "text", payload: .object([:]))]
        )
        let note = try TemplateInstantiator.makeNote(from: template, in: context)

        #expect(note.createdAt >= before)
        #expect(note.createdAt <= Date())
        #expect(note.modifiedAt == note.createdAt)
    }
}
