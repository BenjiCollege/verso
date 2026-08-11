import Foundation

struct RatingPayload: BlockPayload {
    static let blockType = BlockType.rating

    enum Symbol: String, Codable, CaseIterable, Sendable {
        case star
        case circle
        case heart
        case bolt

        var displayName: LocalizedStringResource {
            switch self {
            case .star: "Stars"
            case .circle: "Circles"
            case .heart: "Hearts"
            case .bolt: "Bolts"
            }
        }

        var filledImage: String {
            switch self {
            case .star: "star.fill"
            case .circle: "circle.fill"
            case .heart: "heart.fill"
            case .bolt: "bolt.fill"
            }
        }

        var emptyImage: String {
            switch self {
            case .star: "star"
            case .circle: "circle"
            case .heart: "heart"
            case .bolt: "bolt"
            }
        }
    }

    var label: String
    /// How many marks. Clamped to something a thumb can actually hit.
    var scale: Int
    /// `nil` means unrated, which is different from rated zero.
    var value: Int?
    var symbol: Symbol

    init(label: String = "", scale: Int = 5, value: Int? = nil, symbol: Symbol = .star) {
        let clamped = RatingPayload.clampScale(scale)
        self.label = label
        self.scale = clamped
        self.value = value.map { min(max($0, 0), clamped) }
        self.symbol = symbol
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        let scale = RatingPayload.clampScale(try container.decodeIfPresent(Int.self, forKey: .scale) ?? 5)
        let value = try container.decodeIfPresent(Int.self, forKey: .value)
        let rawSymbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? Symbol.star.rawValue
        self.init(
            label: label,
            scale: scale,
            value: value,
            symbol: Symbol(rawValue: rawSymbol) ?? .star
        )
    }

    static func clampScale(_ scale: Int) -> Int {
        min(max(scale, 2), 10)
    }

    static func makeDefault() -> RatingPayload {
        RatingPayload()
    }

    var plainTextRepresentation: String { label }

    func resetForTemplate() -> RatingPayload {
        var copy = self
        copy.value = nil
        return copy
    }
}
