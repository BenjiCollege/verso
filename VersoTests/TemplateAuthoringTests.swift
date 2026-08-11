import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Decomposition")
struct DecompositionTests {

    private let metric = Decomposition.kilogramBarbell

    @Test("A bare bar needs no plates")
    func bareBar() {
        let result = metric.decompose(20)
        #expect(result.stacks.isEmpty)
        #expect(result.achieved == 20)
        #expect(result.isExact)
    }

    @Test("Common loads decompose exactly", arguments: [
        (100.0, 40.0),
        (60.0, 20.0),
        (142.5, 61.25),
        (25.0, 2.5),
    ])
    func exactLoads(target: Double, perSide: Double) {
        let result = metric.decompose(target)
        let loaded = result.stacks.reduce(0) { $0 + $1.value * Double($1.count) }

        #expect(result.isExact, "\(target) left \(result.remainder)")
        #expect(abs(loaded - perSide) < 0.001)
        #expect(abs(result.achieved - target) < 0.001)
    }

    @Test("The largest plates are used first")
    func greedyOrder() {
        let result = metric.decompose(100)
        #expect(result.stacks.first?.value == 25)
        #expect(result.stacks.map(\.value) == result.stacks.map(\.value).sorted(by: >))
    }

    /// Greedy is exact for canonical plate sets. When it cannot be, the
    /// shortfall has to be shown rather than rounded away.
    @Test("An unreachable load reports the shortfall instead of lying")
    func remainderIsReported() {
        let sparse = Decomposition(base: 20, units: [20], paired: true, unit: "kg")
        let result = sparse.decompose(75)

        #expect(!result.isExact)
        #expect(result.achieved == 60)
        #expect(abs(result.remainder - 15) < 0.001)
    }

    @Test("A target below the bar loads nothing")
    func belowTheBar() {
        let result = metric.decompose(10)
        #expect(result.stacks.isEmpty)
        #expect(result.achieved == 20)
    }

    @Test("Unpaired decomposition uses the whole amount")
    func unpaired() {
        let single = Decomposition(base: 0, units: [10, 5, 1], paired: false, unit: "")
        let result = single.decompose(26)

        #expect(result.stacks.map(\.count) == [2, 1, 1])
        #expect(result.achieved == 26)
    }

    @Test("Pound plates work as well as kilo ones")
    func poundBar() {
        let result = Decomposition.poundBarbell.decompose(225)
        #expect(result.isExact)
        #expect(result.achieved == 225)
    }

    @Test("The display shows how it is actually loaded")
    func displayText() {
        #expect(metric.decompose(100).displayText.contains("2 ×"))
        #expect(metric.decompose(20).displayText == "20")
    }

    @Test("Zero and negative denominations are discarded")
    func invalidUnitsAreDropped() {
        #expect(Decomposition(units: [10, 0, -5]).units == [10])
    }

    /// 1.25kg plates and binary floating point do not get along; without
    /// rounding the accumulated drift the last plate goes missing.
    @Test("Fine denominations do not drift")
    func noFloatingPointDrift() {
        let result = metric.decompose(22.5)
        #expect(result.isExact)
        #expect(result.stacks == [.init(value: 1.25, count: 1)])
    }
}

@Suite("Template authoring")
struct TemplateAuthoringTests {

    private func makeNote(in context: ModelContext) throws -> Note {
        let note = Note(title: "Weekly Shop", themeID: "foxed", stockID: "ruled")
        context.insert(note)

        for payload in [
            try Block(HeadingPayload(level: .two, text: "Shopping")),
            try Block(ChecklistPayload(
                groupBy: .group,
                groups: [.init(id: "produce", label: "Produce", position: 0)],
                itemFields: [.price, .quantity],
                items: [
                    .init(label: "Lemons", checked: true, checkedAt: Date(), price: Decimal(string: "3.49"), group: "produce"),
                    .init(label: "Bread", group: "produce"),
                ]
            )),
            try Block(MetricPayload(label: "Spend", value: 42, unit: "GBP", seriesID: "spend")),
            try Block(RatingPayload(label: "Queue", scale: 5, value: 2)),
        ] {
            context.insert(payload)
            note.append(payload)
        }
        return note
    }

    @Test("A note becomes a template with the same blocks in the same order")
    func structureIsPreserved() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)

        let template = try TemplateAuthoring.makeTemplate(from: note, name: "Shop", keepContents: false)

        #expect(template.blocks.map(\.type) == ["heading", "checklist", "metric", "rating"])
        #expect(template.isUserAuthored)
        #expect(template.themeID == "foxed")
        #expect(template.stockID == "ruled")
        #expect(template.titleFormat == "Weekly Shop")
    }

    /// A template is a shape. Handing one to somebody must not hand over last
    /// week's shopping along with it.
    @Test("Saving without contents keeps structure and drops personal data")
    func resettingClearsContents() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)

        let template = try TemplateAuthoring.makeTemplate(from: note, name: "Shop", keepContents: false)
        let rebuilt = try TemplateInstantiator.makeNote(from: template, in: context)

        let checklist = try rebuilt.orderedBlocks[1].decoded(as: ChecklistPayload.self)
        #expect(checklist.groups.map(\.label) == ["Produce"], "the groups are structure")
        #expect(checklist.itemFields == [.price, .quantity], "which fields show is structure")
        #expect(checklist.items.map(\.label) == ["Lemons", "Bread"], "the items are the list")
        #expect(checklist.items.allSatisfy { !$0.checked }, "the ticks are not")
        #expect(checklist.items.allSatisfy { $0.price == nil }, "and neither is what you paid")

        #expect(try rebuilt.orderedBlocks[2].decoded(as: MetricPayload.self).value == nil)
        #expect(try rebuilt.orderedBlocks[2].decoded(as: MetricPayload.self).seriesID == "spend")
        #expect(try rebuilt.orderedBlocks[3].decoded(as: RatingPayload.self).value == nil)
        #expect(try rebuilt.orderedBlocks[3].decoded(as: RatingPayload.self).scale == 5)
    }

    @Test("Saving with contents keeps everything")
    func keepingContentsPreservesData() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)

        let template = try TemplateAuthoring.makeTemplate(from: note, name: "Shop", keepContents: true)
        let rebuilt = try TemplateInstantiator.makeNote(from: template, in: context)

        let checklist = try rebuilt.orderedBlocks[1].decoded(as: ChecklistPayload.self)
        #expect(checklist.items[0].checked)
        #expect(checklist.items[0].price == Decimal(string: "3.49"))
        #expect(try rebuilt.orderedBlocks[2].decoded(as: MetricPayload.self).value == 42)
    }

    /// The whole round trip: note to template file to note.
    @Test("A template survives being written out and read back")
    func exportImportRoundTrip() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)
        let template = try TemplateAuthoring.makeTemplate(from: note, name: "Shop", keepContents: false)

        let encoder = JSONEncoder()
        let data = try encoder.encode(template)
        let restored = try JSONDecoder().decode(Template.self, from: data)

        #expect(restored.name == template.name)
        #expect(restored.blocks == template.blocks)
        #expect(restored.themeID == template.themeID)

        // The discriminator has to survive, or an exported file imports as
        // nothing.
        let probe = try JSONDecoder().decode([String: JSONValue].self, from: data)
        #expect(probe["kind"] == .string("template"))
    }

    @Test("A block type this build cannot read is skipped rather than corrupting the template")
    func unknownBlocksAreSkipped() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = Note(title: "Mixed")
        context.insert(note)

        let good = try Block(HeadingPayload(level: .one, text: "Kept"))
        let alien = Block(typeRaw: "hologram", payload: Data())
        context.insert(good)
        context.insert(alien)
        note.append(good)
        note.append(alien)

        let template = try TemplateAuthoring.makeTemplate(from: note, name: "Mixed", keepContents: true)
        #expect(template.blocks.map(\.type) == ["heading"])
    }

    @Test("Every saved template gets a distinct id")
    func idsAreDistinct() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try makeNote(in: context)

        let first = try TemplateAuthoring.makeTemplate(from: note, name: "A", keepContents: false)
        let second = try TemplateAuthoring.makeTemplate(from: note, name: "A", keepContents: false)
        #expect(first.id != second.id)
    }

    @Test("An untitled note suggests a name rather than inheriting nothing")
    func suggestedName() throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let untitled = Note()
        context.insert(untitled)

        #expect(!TemplateAuthoring.suggestedName(for: untitled).isEmpty)
        let template = try TemplateAuthoring.makeTemplate(from: untitled, name: "X", keepContents: false)
        #expect(template.titleFormat == nil, "Untitled is not worth inheriting")
    }
}

@Suite("User template store")
@MainActor
struct UserTemplateStoreTests {

    private func makeStore() -> UserTemplateStore {
        let directory = URL.temporaryDirectory.appending(path: "VersoTests-\(UUID().uuidString)")
        return UserTemplateStore(directory: directory)
    }

    private func sample(name: String = "Mine") -> Template {
        var template = Template(
            id: "user.\(UUID().uuidString)",
            name: name,
            summary: "A test",
            category: "custom",
            blocks: [.init(type: "heading", payload: ["level": 2, "text": "Hello"])]
        )
        template.isUserAuthored = true
        return template
    }

    @Test("Saving then reloading returns the template")
    func saveAndReload() {
        let store = makeStore()
        let template = sample()

        #expect(store.save(template))
        #expect(store.templates.map(\.id) == [template.id])
        #expect(store.templates[0].isUserAuthored)

        store.reload()
        #expect(store.templates.count == 1)
    }

    @Test("Deleting removes it")
    func delete() {
        let store = makeStore()
        let template = sample()
        store.save(template)

        store.delete(id: template.id)
        #expect(store.templates.isEmpty)
    }

    @Test("Renaming keeps the id")
    func rename() {
        let store = makeStore()
        let template = sample(name: "Before")
        store.save(template)

        store.rename(id: template.id, to: "After")
        #expect(store.templates.map(\.name) == ["After"])
        #expect(store.templates.map(\.id) == [template.id])
    }

    @Test("Templates are listed alphabetically, not in filesystem order")
    func sortedByName() {
        let store = makeStore()
        store.save(sample(name: "Zebra"))
        store.save(sample(name: "Apple"))
        store.save(sample(name: "Mango"))

        #expect(store.templates.map(\.name) == ["Apple", "Mango", "Zebra"])
    }

    @Test("Exported bytes import back as an equivalent template")
    func exportImport() throws {
        let store = makeStore()
        let original = sample(name: "Shared")
        store.save(original)

        let data = try store.exportData(for: original)
        let other = makeStore()
        let imported = try #require(other.importTemplate(from: data))

        #expect(imported.name == "Shared")
        #expect(imported.blocks == original.blocks)
        #expect(imported.isUserAuthored)
    }

    /// Importing the same file twice must not silently replace the first copy.
    @Test("Importing mints a new id")
    func importMintsANewID() throws {
        let store = makeStore()
        let original = sample()
        let data = try store.exportData(for: original)

        let first = try #require(store.importTemplate(from: data))
        let second = try #require(store.importTemplate(from: data))

        #expect(first.id != second.id)
        #expect(first.id != original.id)
        #expect(store.templates.count == 2)
    }

    @Test("Rubbish does not import, and says so")
    func badImportIsReported() {
        let store = makeStore()
        #expect(store.importTemplate(from: Data("not a template".utf8)) == nil)
        #expect(store.lastError?.isEmpty == false)
        #expect(store.templates.isEmpty)
    }

    /// Template names come from the user and end up as filenames.
    @Test("A name full of path characters still saves")
    func hostileNamesAreSanitised() {
        let store = makeStore()
        var template = sample(name: "../../etc/passwd")
        template.id = "user.../../escape"

        #expect(store.save(template))
        #expect(store.templates.count == 1)
    }

    @Test("An empty store is empty rather than failing")
    func emptyStore() {
        #expect(makeStore().templates.isEmpty)
    }
}
