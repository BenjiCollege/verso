import Foundation

struct DividerPayload: BlockPayload {
    static let blockType = BlockType.divider

    enum Style: String, Codable, CaseIterable, Sendable {
        /// A hairline in the theme's rule colour.
        case rule
        /// Three widely-spaced dots — a section break that doesn't cut the page.
        case dots
        /// A centred typographic ornament.
        case fleuron
        /// Vertical air and nothing drawn at all.
        case space

        var displayName: LocalizedStringResource {
            switch self {
            case .rule: "Rule"
            case .dots: "Dots"
            case .fleuron: "Ornament"
            case .space: "Space"
            }
        }
    }

    var style: Style

    init(style: Style = .rule) {
        self.style = style
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawStyle = try container.decodeIfPresent(String.self, forKey: .style) ?? Style.rule.rawValue
        self.style = Style(rawValue: rawStyle) ?? .rule
    }

    static func makeDefault() -> DividerPayload {
        DividerPayload(style: .rule)
    }
}
