import Foundation

struct ProgressPayload: BlockPayload {
    static let blockType = BlockType.progress

    enum Style: String, Codable, CaseIterable, Sendable {
        case bar
        case ring
        /// One mark per unit — legible at a glance for small targets, which is
        /// what habit and hydration counts are.
        case dots

        var displayName: LocalizedStringResource {
            switch self {
            case .bar: "Bar"
            case .ring: "Ring"
            case .dots: "Dots"
            }
        }
    }

    var label: String
    var current: Double
    var target: Double
    var style: Style

    init(label: String = "", current: Double = 0, target: Double = 1, style: Style = .bar) {
        self.label = label
        self.current = current
        self.target = target
        self.style = style
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.current = try container.decodeIfPresent(Double.self, forKey: .current) ?? 0
        self.target = try container.decodeIfPresent(Double.self, forKey: .target) ?? 1
        let rawStyle = try container.decodeIfPresent(String.self, forKey: .style) ?? Style.bar.rawValue
        self.style = Style(rawValue: rawStyle) ?? .bar
    }

    static func makeDefault() -> ProgressPayload {
        ProgressPayload()
    }

    var plainTextRepresentation: String { label }

    /// Clamped to 0...1. Overshooting a target is worth celebrating, not worth
    /// drawing a bar past the end of itself.
    var fraction: Double {
        guard target != 0 else { return 0 }
        return min(max(current / target, 0), 1)
    }

    var isComplete: Bool { target != 0 && current >= target }
}
