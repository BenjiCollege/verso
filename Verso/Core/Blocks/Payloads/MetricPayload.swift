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

    // MARK: Capabilities
    //
    // Four options, all JSON-driven and all generic. Between them they cover
    // every strength non-negotiable in section 7 without a single reference to
    // a template id, an exercise, or a barbell anywhere in Swift.

    /// Shows the last reading in this series while logging the next one.
    /// Section 7 asks for it in strength sessions; it is just as useful for
    /// bodyweight or a resting heart rate.
    var showsPreviousEntry: Bool

    /// Starts a countdown once a value is committed. A rest timer between sets,
    /// or a wait between doses — the metric has a cooldown, and the engine has
    /// no opinion about what it is a cooldown from.
    var restTimerSeconds: TimeInterval?

    /// Expresses the value as a stack of available units. Plate maths, without
    /// the engine knowing what a plate is.
    var decomposition: Decomposition?

    /// A `Catalog` to pick the label and series from — `"exercises"`, say.
    /// Turning a catalog into a picker is the engine's job; knowing what is in
    /// it is the JSON's.
    var catalogID: String?

    init(
        label: String = "",
        value: Double? = nil,
        unit: String = "",
        target: Double? = nil,
        seriesID: String = "",
        groupID: String? = nil,
        showsPreviousEntry: Bool = false,
        restTimerSeconds: TimeInterval? = nil,
        decomposition: Decomposition? = nil,
        catalogID: String? = nil
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.target = target
        self.seriesID = seriesID
        self.groupID = groupID
        self.showsPreviousEntry = showsPreviousEntry
        self.restTimerSeconds = restTimerSeconds
        self.decomposition = decomposition
        self.catalogID = catalogID
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
        self.showsPreviousEntry = try container.decodeIfPresent(Bool.self, forKey: .showsPreviousEntry) ?? false
        self.restTimerSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .restTimerSeconds)
        self.decomposition = try container.decodeIfPresent(Decomposition.self, forKey: .decomposition)
        self.catalogID = try container.decodeIfPresent(String.self, forKey: .catalogID)
    }

    static func makeDefault() -> MetricPayload {
        MetricPayload()
    }

    /// Saved as a template, a metric keeps its shape and loses its reading.
    func resetForTemplate() -> MetricPayload {
        var copy = self
        copy.value = nil
        return copy
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
