import Foundation

struct ListPayload: BlockPayload {
    static let blockType = BlockType.list

    enum Style: String, Codable, CaseIterable, Sendable {
        case bullet
        case numbered

        var displayName: LocalizedStringResource {
            switch self {
            case .bullet: "Bulleted"
            case .numbered: "Numbered"
            }
        }
    }

    struct Item: Codable, Hashable, Identifiable, Sendable {
        var id: UUID
        var text: String

        init(id: UUID = UUID(), text: String = "") {
            self.id = id
            self.text = text
        }
    }

    var style: Style
    var items: [Item]

    init(style: Style = .bullet, items: [Item] = []) {
        self.style = style
        self.items = items
    }

    /// An unrecognised style falls back to bullets.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawStyle = try container.decodeIfPresent(String.self, forKey: .style) ?? Style.bullet.rawValue
        self.style = Style(rawValue: rawStyle) ?? .bullet
        self.items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
    }

    static func makeDefault() -> ListPayload {
        ListPayload(style: .bullet, items: [Item()])
    }

    var plainTextRepresentation: String {
        items.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
