import Foundation

/// A note reduced to text, which is all any provider is given.
///
/// Built once and passed around, so nothing in the intelligence layer touches
/// a `ModelContext`, and so a locked note can be excluded in exactly one place.
struct NoteDigest: Sendable, Equatable {
    var title: String
    var blocks: [String]

    var text: String {
        ([title] + blocks).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    @MainActor
    init(_ note: Note, registry: BlockRegistry = .shared) {
        // A locked note is ciphertext; there is nothing to read and nothing
        // should try.
        guard !note.isLocked else {
            self.title = ""
            self.blocks = []
            return
        }
        self.title = note.title
        self.blocks = note.orderedBlocks
            .map { registry.plainText(for: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    init(title: String = "", blocks: [String] = []) {
        self.title = title
        self.blocks = blocks
    }
}

/// A note the app has been asked to construct — from a paste, or from speech.
///
/// Deliberately shaped like a `Template`, because instantiation is already
/// built and tested. Whether this came from a language model or from a regular
/// expression, it becomes a note the same way.
struct CapturedNote: Sendable, Equatable {

    struct Item: Sendable, Equatable {
        var label: String
        var quantity: Double?
        var unit: String?
        /// A section key, matched against `Section.key`.
        var group: String?

        init(label: String, quantity: Double? = nil, unit: String? = nil, group: String? = nil) {
            self.label = label
            self.quantity = quantity
            self.unit = unit
            self.group = group
        }
    }

    struct Section: Sendable, Equatable {
        var key: String
        var heading: String
        var items: [Item]
        var prose: String

        init(key: String = UUID().uuidString, heading: String = "", items: [Item] = [], prose: String = "") {
            self.key = key
            self.heading = heading
            self.items = items
            self.prose = prose
        }
    }

    var title: String
    var sections: [Section]

    init(title: String = "", sections: [Section] = []) {
        self.title = title
        self.sections = sections
    }

    var isEmpty: Bool {
        sections.allSatisfy { $0.items.isEmpty && $0.prose.isEmpty } && title.isEmpty
    }

    var itemCount: Int { sections.reduce(0) { $0 + $1.items.count } }
}

extension CapturedNote {
    /// Converts to a template, so the note is built by the same instantiator
    /// everything else uses.
    ///
    /// Sections with items become one grouped checklist; prose becomes text
    /// blocks under headings. Nothing here knows what a recipe is — it knows
    /// that some things are lists and some things are paragraphs.
    func makeTemplate(id: String = "capture." + UUID().uuidString) -> Template {
        var blocks: [Template.BlockSpec] = []

        let listSections = sections.filter { !$0.items.isEmpty }
        let proseSections = sections.filter { $0.items.isEmpty && !$0.prose.isEmpty }

        if !listSections.isEmpty {
            let groups: [JSONValue] = listSections.enumerated().map { index, section in
                .object([
                    "id": .string(section.key),
                    "label": .string(section.heading),
                    "position": .number(Double(index)),
                ])
            }

            let items: [JSONValue] = listSections.flatMap { section in
                section.items.map { item in
                    var fields: [String: JSONValue] = [
                        "label": .string(item.label),
                        "group": .string(section.key),
                    ]
                    if let quantity = item.quantity { fields["quantity"] = .number(quantity) }
                    if let unit = item.unit, !unit.isEmpty { fields["unit"] = .string(unit) }
                    return .object(fields)
                }
            }

            // Fields are offered only when something actually uses them, so a
            // packing list does not sprout price columns.
            var fields: [JSONValue] = []
            if items.contains(where: { $0["quantity"] != nil }) { fields.append(.string("quantity")) }
            if items.contains(where: { $0["unit"] != nil }) { fields.append(.string("unit")) }
            fields.append(.string("note"))

            blocks.append(
                Template.BlockSpec(
                    type: BlockType.checklist.rawValue,
                    payload: .object([
                        "groupBy": .string(listSections.count > 1 ? "group" : "none"),
                        "groups": .array(groups),
                        "itemFields": .array(fields),
                        "items": .array(items),
                    ])
                )
            )
        }

        for section in proseSections {
            if !section.heading.isEmpty {
                blocks.append(
                    Template.BlockSpec(
                        type: BlockType.heading.rawValue,
                        payload: .object(["level": .number(2), "text": .string(section.heading)])
                    )
                )
            }
            blocks.append(
                Template.BlockSpec(
                    type: BlockType.text.rawValue,
                    payload: .object(["plain": .string(section.prose)])
                )
            )
        }

        if blocks.isEmpty {
            blocks.append(
                Template.BlockSpec(type: BlockType.text.rawValue, payload: .object(["plain": .string("")]))
            )
        }

        return Template(
            id: id,
            name: title.isEmpty ? String(localized: "Captured") : title,
            systemImage: "sparkles",
            titleFormat: title.isEmpty ? nil : title,
            blocks: blocks
        )
    }
}

/// What the app can ask for.
///
/// Two implementations: one backed by the on-device language model, one by
/// ordinary text processing. Section 1 requires the second to exist and to be
/// genuinely useful — the app has to be fully usable on a device with no Apple
/// Intelligence support, which means the fallback is a feature, not a stub.
protocol IntelligenceProvider: Sendable {
    /// A short title for an untitled note.
    func suggestTitle(for digest: NoteDigest) async -> String?

    /// Tags for a note, constrained to ones that already exist. Section 7 is
    /// explicit: suggestion, not invention — a tag vocabulary that grows itself
    /// stops being a vocabulary.
    func suggestTags(for digest: NoteDigest, existing: [String]) async -> [String]

    /// Three bullets. Not four.
    func summarise(_ digest: NoteDigest) async -> [String]

    /// Things that look like actions. Offered, never applied.
    func extractActions(from digest: NoteDigest) async -> [String]

    /// Free text — pasted or spoken — turned into a structured note.
    func structure(_ text: String) async -> CapturedNote
}
