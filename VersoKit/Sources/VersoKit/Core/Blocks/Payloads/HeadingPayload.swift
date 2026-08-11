import Foundation

struct HeadingPayload: BlockPayload {
    static let blockType = BlockType.heading

    /// Three levels, mapping onto the 26 / 20 / 17 steps of the type scale.
    enum Level: Int, Codable, CaseIterable, Sendable {
        case one = 1
        case two = 2
        case three = 3

        var displayName: LocalizedStringResource {
            switch self {
            case .one: "Heading 1"
            case .two: "Heading 2"
            case .three: "Heading 3"
            }
        }
    }

    var level: Level
    var text: String

    init(level: Level = .one, text: String = "") {
        self.level = level
        self.text = text
    }

    /// An out-of-range level from a future build clamps rather than throws.
    /// A heading rendered one step off is a far better outcome than a note
    /// that refuses to open.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawLevel = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
        self.level = Level(rawValue: min(max(rawLevel, 1), 3)) ?? .one
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }

    static func makeDefault() -> HeadingPayload {
        HeadingPayload(level: .two, text: "")
    }

    var plainTextRepresentation: String { text }
}
