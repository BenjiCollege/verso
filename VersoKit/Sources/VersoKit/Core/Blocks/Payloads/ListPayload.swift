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

        /// Both keys optional, like every other nested payload type.
        ///
        /// A template is JSON somebody writes by hand, and nobody hand-writes
        /// a UUID per bullet. Section 2 promises a new template is one file and
        /// no Swift; a synthesised decoder that demands `id` quietly breaks
        /// that promise for every list block in the library.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
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
