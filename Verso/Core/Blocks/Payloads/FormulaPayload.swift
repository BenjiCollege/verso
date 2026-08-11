import Foundation

/// A computed number.
///
/// The expression is evaluated against a context the note builds from its own
/// blocks — see `FormulaContextBuilder`. The formula language knows about
/// numbers and lists of numbers; it does not know what a subtotal or a volume
/// load is, and neither does this file.
struct FormulaPayload: BlockPayload {
    static let blockType = BlockType.formula

    var label: String
    var expression: String

    init(label: String = "", expression: String = "") {
        self.label = label
        self.expression = expression
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.expression = try container.decodeIfPresent(String.self, forKey: .expression) ?? ""
    }

    static func makeDefault() -> FormulaPayload {
        FormulaPayload()
    }

    var plainTextRepresentation: String { label }
}
