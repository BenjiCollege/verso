import Foundation

/// A single measured number.
///
/// `seriesID` is the load-bearing field. Every metric in the app — a bench
/// press, a glass of water, a bodyweight reading — writes into the one
/// `MetricEntry` store under its series, which is what makes charting any of
/// them the same query.
struct MetricPayload: BlockPayload {
    static let blockType = BlockType.metric

    var label: String
    /// Optional because an unfilled metric is not a measurement of zero.
    var value: Double?
    var unit: String
    var target: Double?

    /// The series this reading belongs to. Slugged, stable, and shared across
    /// notes: two workout notes six months apart both write to `bench-press`.
    var seriesID: String

    /// Groups readings that were taken together — the sets within one exercise.
    /// Also what identifies *this block's* row in the series, so an edit
    /// updates a reading rather than appending a duplicate.
    var groupID: String?

    init(
        label: String = "",
        value: Double? = nil,
        unit: String = "",
        target: Double? = nil,
        seriesID: String = "",
        groupID: String? = nil
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.target = target
        self.seriesID = seriesID
        self.groupID = groupID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.value = try container.decodeIfPresent(Double.self, forKey: .value)
        self.unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        self.target = try container.decodeIfPresent(Double.self, forKey: .target)
        let declared = try container.decodeIfPresent(String.self, forKey: .seriesID) ?? ""
        // A template may leave the series to be derived from the label, so that
        // an author writing a new exercise file does not have to hand-slug it.
        self.seriesID = declared.isEmpty ? MetricPayload.slug(label) : declared
        self.groupID = try container.decodeIfPresent(String.self, forKey: .groupID)
    }

    static func makeDefault() -> MetricPayload {
        MetricPayload()
    }

    var plainTextRepresentation: String {
        guard let value else { return label }
        let formatted = value.formatted(.number.precision(.fractionLength(0...2)))
        return unit.isEmpty ? "\(label) \(formatted)" : "\(label) \(formatted) \(unit)"
    }

    /// Lowercase, hyphenated, ASCII-safe. Two notes that name the same thing
    /// must land on the same series, so this has to be stable and boring.
    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let pieces = folded.split { !$0.isLetter && !$0.isNumber }
        return pieces.joined(separator: "-").lowercased()
    }

    var fractionOfTarget: Double? {
        guard let value, let target, target != 0 else { return nil }
        return value / target
    }
}
