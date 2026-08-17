import Foundation
import Testing
@testable import VersoKit

@Suite("Block payload round-trip")
struct BlockPayloadRoundTripTests {

    // MARK: - Round-trip

    @Test("Text payload survives encode/decode")
    func textRoundTrip() throws {
        var attributed = AttributedString("Iron gall ink bites into the paper.")
        attributed.inlinePresentationIntent = .stronglyEmphasized
        let original = TextPayload(attributed)

        let data = try BlockCoding.encode(original)
        let restored = try BlockCoding.decode(TextPayload.self, from: data)

        #expect(restored == original)
        #expect(restored.plain == "Iron gall ink bites into the paper.")
        #expect(String(restored.attributed.characters) == original.plain)
    }

    @Test("Heading payload survives encode/decode", arguments: HeadingPayload.Level.allCases)
    func headingRoundTrip(level: HeadingPayload.Level) throws {
        let original = HeadingPayload(level: level, text: "Fore-edge")
        let restored = try BlockCoding.decode(HeadingPayload.self, from: BlockCoding.encode(original))
        #expect(restored == original)
    }

    @Test("List payload survives encode/decode", arguments: ListPayload.Style.allCases)
    func listRoundTrip(style: ListPayload.Style) throws {
        let original = ListPayload(style: style, items: [
            .init(text: "Quires"),
            .init(text: "Signatures"),
            .init(text: "Gatherings"),
        ])
        let restored = try BlockCoding.decode(ListPayload.self, from: BlockCoding.encode(original))
        #expect(restored == original)
        #expect(restored.items.map(\.id) == original.items.map(\.id))
    }

    @Test("Divider payload survives encode/decode", arguments: DividerPayload.Style.allCases)
    func dividerRoundTrip(style: DividerPayload.Style) throws {
        let original = DividerPayload(style: style)
        let restored = try BlockCoding.decode(DividerPayload.self, from: BlockCoding.encode(original))
        #expect(restored == original)
    }

    @Test("Fully-populated checklist item survives encode/decode")
    func checklistRoundTrip() throws {
        let checkedAt = Date(timeIntervalSince1970: 1_760_000_000)
        let original = ChecklistPayload(
            groupBy: .group,
            groups: [
                .init(id: "produce", label: "Produce", position: 0),
                .init(id: "dairy", label: "Dairy", position: 1),
            ],
            itemFields: [.quantity, .unit, .price, .note],
            items: [
                .init(
                    label: "Lemons",
                    checked: true,
                    checkedAt: checkedAt,
                    quantity: 6,
                    unit: "ea",
                    price: Decimal(string: "3.49"),
                    currency: "USD",
                    group: "produce",
                    note: "Unwaxed if they have them",
                    tags: ["citrus"],
                    schedule: .init(dueAt: checkedAt, recurrence: "FREQ=WEEKLY"),
                    place: .init(latitude: 51.5, longitude: -0.12, poiCategory: "MKPOICategoryFoodMarket", radius: 200),
                    image: .init(assetID: UUID(), caption: "Shelf tag"),
                    link: .init(url: URL(string: "https://example.com/lemons"), noteID: UUID())
                ),
                .init(label: "Butter", group: "dairy"),
            ]
        )

        let restored = try BlockCoding.decode(ChecklistPayload.self, from: BlockCoding.encode(original))
        #expect(restored == original)
        #expect(restored.items[0].price == Decimal(string: "3.49"))
        #expect(restored.items[0].checkedAt == checkedAt)
    }

    // MARK: - Determinism

    @Test("Encoding the same payload twice produces identical bytes")
    func encodingIsDeterministic() throws {
        let payload = ChecklistPayload(
            groupBy: .group,
            groups: [.init(id: "b", label: "B", position: 1), .init(id: "a", label: "A", position: 0)],
            itemFields: [.price, .quantity],
            items: [.init(label: "One"), .init(label: "Two")]
        )
        #expect(try BlockCoding.encode(payload) == BlockCoding.encode(payload))
    }

    // MARK: - Block <-> payload

    @Test("Block stores and returns its payload")
    func blockStoresPayload() throws {
        let payload = HeadingPayload(level: .two, text: "Verso")
        let block = try Block(payload, position: 3)

        #expect(block.typeRaw == BlockType.heading.rawValue)
        #expect(block.type == .heading)
        #expect(block.position == 3)
        #expect(try block.decoded(as: HeadingPayload.self) == payload)
    }

    @Test("Decoding a block as the wrong payload type throws")
    func blockTypeMismatchThrows() throws {
        let block = try Block(DividerPayload(style: .dots))
        #expect(throws: BlockRegistryError.typeMismatch(expected: "heading", found: "divider")) {
            _ = try block.decoded(as: HeadingPayload.self)
        }
    }

    // MARK: - Registry

    @Test("Registry decodes every implemented type through the existential path")
    func registryDecodesAllImplementedTypes() throws {
        for type in BlockRegistry.shared.implementedTypes {
            let data = try BlockRegistry.shared.makeDefaultData(for: type)
            let payload = try BlockRegistry.shared.decode(data, as: type)
            #expect(Swift.type(of: payload).blockType == type)
        }
    }

    @Test("The registry implements exactly the types shipped so far")
    func registryImplementsShippedTypes() {
        #expect(BlockRegistry.shared.implementedTypes == [
            .text, .heading, .checklist, .list,
            .metric, .timer, .table, .place, .schedule, .formula, .progress, .rating,
            .divider, .image, .sketch, .audio, .attachment,
        ])
    }

    /// Three remain: `callout`, `code` and `link` have no phase of their own, so
    /// the registry still has to refuse cleanly.
    @Test("Registry refuses a type it has no payload for")
    func registryRejectsUnimplementedType() {
        #expect(!BlockRegistry.shared.isImplemented(.callout))
        #expect(throws: BlockRegistryError.unimplementedType(.callout)) {
            _ = try BlockRegistry.shared.makeDefaultData(for: .callout)
        }
    }

    @Test("Registry transcodes inline template JSON through the real payload type")
    func registryTranscodesJSON() throws {
        let json: JSONValue = [
            "style": "numbered",
            "items": [["text": "First"], ["text": "Second"]],
        ]
        let data = try BlockRegistry.shared.transcode(json, as: .list)
        let payload = try BlockCoding.decode(ListPayload.self, from: data)

        #expect(payload.style == .numbered)
        #expect(payload.items.map(\.text) == ["First", "Second"])
        // Ids are absent from the JSON and minted during transcode.
        #expect(Set(payload.items.map(\.id)).count == 2)
    }

    @Test("Registry rejects a malformed template payload rather than silently emptying it")
    func registryRejectsMalformedJSON() {
        let json: JSONValue = ["level": "not-a-number"]
        #expect(throws: (any Error).self) {
            _ = try BlockRegistry.shared.transcode(json, as: .heading)
        }
    }

    // MARK: - Forward compatibility

    @Test("A block written by a newer build degrades instead of throwing")
    func unknownBlockTypeDegrades() {
        let block = Block(typeRaw: "hologram", payload: Data())
        #expect(block.type == nil)
        #expect(BlockRegistry.shared.plainText(for: block).isEmpty)
        #expect(throws: BlockRegistryError.unknownType("hologram")) {
            _ = try block.decodedPayload()
        }
    }

    @Test("An out-of-range heading level clamps")
    func headingLevelClamps() throws {
        let data = Data(#"{"level":9,"text":"Loud"}"#.utf8)
        let payload = try BlockCoding.decode(HeadingPayload.self, from: data)
        #expect(payload.level == .three)
        #expect(payload.text == "Loud")
    }

    @Test("Unknown checklist grouping and item fields are dropped, not fatal")
    func checklistDropsUnknownEnumCases() throws {
        let data = Data(#"{"groupBy":"phase-of-moon","itemFields":["price","holograph"],"groups":[],"items":[]}"#.utf8)
        let payload = try BlockCoding.decode(ChecklistPayload.self, from: data)
        #expect(payload.groupBy == .none)
        #expect(payload.itemFields == [.price])
    }

    @Test("An empty text archive falls back to the plain mirror")
    func textFallsBackToPlain() {
        let payload = TextPayload(archive: Data(), plain: "Recovered")
        #expect(String(payload.attributed.characters) == "Recovered")
    }

    // MARK: - Checklist sectioning

    @Test("Grouped checklist sections follow group position and keep item order")
    func checklistSectionsByGroup() {
        let payload = ChecklistPayload(
            groupBy: .group,
            groups: [
                .init(id: "dairy", label: "Dairy", position: 1),
                .init(id: "produce", label: "Produce", position: 0),
            ],
            items: [
                .init(label: "Butter", group: "dairy"),
                .init(label: "Lemons", group: "produce"),
                .init(label: "Limes", group: "produce"),
            ]
        )

        let sections = payload.sections()
        #expect(sections.map(\.title) == ["Produce", "Dairy"])
        #expect(sections[0].items.map(\.label) == ["Lemons", "Limes"])
    }

    @Test("Items pointing at a missing group survive in a trailing section")
    func checklistKeepsOrphanedItems() {
        let payload = ChecklistPayload(
            groupBy: .group,
            groups: [.init(id: "produce", label: "Produce", position: 0)],
            items: [
                .init(label: "Lemons", group: "produce"),
                .init(label: "Batteries", group: "hardware"),
                .init(label: "Loose"),
            ]
        )

        let sections = payload.sections()
        #expect(sections.count == 2)
        #expect(sections[1].id == "__ungrouped")
        #expect(sections[1].items.map(\.label) == ["Batteries", "Loose"])
    }

    @Test("Checking an item stamps and clears its timestamp")
    func checklistCheckOffStampsDate() {
        var payload = ChecklistPayload(items: [.init(label: "Lemons")])
        let id = payload.items[0].id
        let now = Date(timeIntervalSince1970: 1_760_000_000)

        payload.setChecked(true, itemID: id, at: now)
        #expect(payload.items[0].checked)
        #expect(payload.items[0].checkedAt == now)
        #expect(payload.completionFraction == 1)

        payload.setChecked(false, itemID: id)
        #expect(!payload.items[0].checked)
        #expect(payload.items[0].checkedAt == nil)
        #expect(payload.completionFraction == 0)
    }
}
