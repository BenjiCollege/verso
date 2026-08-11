import Foundation

/// A template is a JSON file. It names block types and supplies their payloads
/// as inline JSON; it contains no logic and no Swift.
///
/// Adding a template must be one new file in `Resources/Templates/` and zero
/// Swift changes. If a template needs behaviour this model can't express, the
/// block system is missing a capability — that is a conversation, not a special
/// case in the instantiator.
struct Template: Identifiable, Hashable, Sendable, Codable {

    struct BlockSpec: Hashable, Sendable, Codable {
        /// Stored as a string so an unrecognised type is a validation failure
        /// with a useful message rather than a decoding error on the whole file.
        var type: String
        var payload: JSONValue

        var blockType: BlockType? { BlockType(rawValue: type) }
    }

    var id: String
    var name: String
    /// One line, shown under the name in the gallery.
    var summary: String?
    var systemImage: String
    /// Free-form grouping key for the Phase 5 gallery. The engine attaches no
    /// meaning to it.
    var category: String?

    /// Appearance the template prefers. `nil` means inherit the app default.
    var themeID: String?
    var stockID: String?
    var revealStyleID: String?

    /// The new note's title, with `{date}`, `{weekday}` and `{time}` substituted
    /// at instantiation. `nil` leaves the title empty for the user to write.
    var titleFormat: String?

    var blocks: [BlockSpec]

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, systemImage, category
        case themeID, stockID, revealStyleID, titleFormat, blocks
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.summary = try container.decodeIfPresent(String.self, forKey: .summary)
        self.systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? "doc.text"
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
        self.themeID = try container.decodeIfPresent(String.self, forKey: .themeID)
        self.stockID = try container.decodeIfPresent(String.self, forKey: .stockID)
        self.revealStyleID = try container.decodeIfPresent(String.self, forKey: .revealStyleID)
        self.titleFormat = try container.decodeIfPresent(String.self, forKey: .titleFormat)
        self.blocks = try container.decodeIfPresent([BlockSpec].self, forKey: .blocks) ?? []
    }

    init(
        id: String,
        name: String,
        summary: String? = nil,
        systemImage: String = "doc.text",
        category: String? = nil,
        themeID: String? = nil,
        stockID: String? = nil,
        revealStyleID: String? = nil,
        titleFormat: String? = nil,
        blocks: [BlockSpec] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.systemImage = systemImage
        self.category = category
        self.themeID = themeID
        self.stockID = stockID
        self.revealStyleID = revealStyleID
        self.titleFormat = titleFormat
        self.blocks = blocks
    }
}

extension Template {
    /// Block types this template names that the running build cannot build.
    /// A template referencing a Phase 3 block simply doesn't appear in the
    /// Phase 1 gallery rather than offering a note that can't be made.
    func unsupportedBlockTypes(using registry: BlockRegistry = .shared) -> [String] {
        blocks.compactMap { spec in
            guard let type = spec.blockType else { return spec.type }
            return registry.isImplemented(type) ? nil : spec.type
        }
    }

    var isSupported: Bool { unsupportedBlockTypes().isEmpty }
}

enum TemplateError: LocalizedError {
    case unknownBlockType(templateID: String, raw: String)
    case unsupportedBlockType(templateID: String, type: BlockType)
    case malformedPayload(templateID: String, index: Int, type: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .unknownBlockType(let templateID, let raw):
            "Template “\(templateID)” uses an unknown block type “\(raw)”."
        case .unsupportedBlockType(let templateID, let type):
            "Template “\(templateID)” uses \(type.rawValue) blocks, which this version of Verso can't create yet."
        case .malformedPayload(let templateID, let index, let type, let underlying):
            "Template “\(templateID)” has a malformed \(type) payload at position \(index): \(underlying)"
        }
    }
}
