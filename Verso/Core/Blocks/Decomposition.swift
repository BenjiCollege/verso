import Foundation

/// Expressing a number as a stack of available denominations.
///
/// This is what plate maths is, stripped of the gym: given a total, a fixed
/// base, and the units you actually own, work out how many of each you need.
/// The engine never learns the word "barbell" — a template supplies the bar
/// weight as `base` and the plates as `units`, and the same code would make
/// change out of coins.
struct Decomposition: Codable, Hashable, Sendable {
    /// Always present before anything is added. The empty bar.
    var base: Double
    /// The denominations available, in any order.
    var units: [Double]
    /// Loaded symmetrically: each unit used costs two of it, and the result is
    /// reported per side.
    var paired: Bool
    /// Display suffix. Purely cosmetic.
    var unit: String

    init(base: Double = 20, units: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25], paired: Bool = true, unit: String = "kg") {
        self.base = base
        self.units = units.filter { $0 > 0 }.sorted(by: >)
        self.paired = paired
        self.unit = unit
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            base: try container.decodeIfPresent(Double.self, forKey: .base) ?? 20,
            units: try container.decodeIfPresent([Double].self, forKey: .units) ?? [],
            paired: try container.decodeIfPresent(Bool.self, forKey: .paired) ?? true,
            unit: try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        )
    }

    static let kilogramBarbell = Decomposition()
    static let poundBarbell = Decomposition(
        base: 45,
        units: [45, 35, 25, 10, 5, 2.5],
        paired: true,
        unit: "lb"
    )
}

struct DecompositionResult: Hashable, Sendable {
    struct Stack: Hashable, Sendable, Identifiable {
        var id: Double { value }
        var value: Double
        var count: Int
    }

    var base: Double
    /// Per side when `paired`, otherwise the whole stack.
    var stacks: [Stack]
    /// What the stacks actually add up to, which may be less than asked for.
    var achieved: Double
    /// What could not be made from the available units. Non-zero means the
    /// answer is a lie unless it is shown.
    var remainder: Double
    var isExact: Bool { remainder < 0.0001 }
    var paired: Bool
    var unit: String

    /// "20 + 2 × (15 + 5)" — the way it is actually loaded.
    var displayText: String {
        guard !stacks.isEmpty else {
            return base.formatted(.number.precision(.fractionLength(0...2)))
        }
        let side = stacks
            .flatMap { Array(repeating: $0.value, count: $0.count) }
            .map { $0.formatted(.number.precision(.fractionLength(0...2))) }
            .joined(separator: " + ")

        let baseText = base.formatted(.number.precision(.fractionLength(0...2)))
        return paired ? "\(baseText) + 2 × (\(side))" : "\(baseText) + \(side)"
    }
}

extension Decomposition {
    /// Greedy from the largest denomination down.
    ///
    /// Greedy is exact for every real plate set, because they are canonical —
    /// each denomination divides into the next. It can leave a remainder for a
    /// contrived set, which is why the remainder is reported rather than
    /// rounded away.
    func decompose(_ target: Double) -> DecompositionResult {
        let perSideTarget = paired ? (target - base) / 2 : target - base
        var remaining = max(0, perSideTarget)
        var stacks: [DecompositionResult.Stack] = []

        for value in units.sorted(by: >) where value > 0 {
            let count = Int((remaining / value).rounded(.down))
            guard count > 0 else { continue }
            stacks.append(.init(value: value, count: count))
            remaining -= Double(count) * value
            // Floating point drift accumulates fast at 1.25kg granularity.
            remaining = (remaining * 1000).rounded() / 1000
        }

        let loaded = stacks.reduce(0) { $0 + $1.value * Double($1.count) }
        let achieved = base + (paired ? loaded * 2 : loaded)

        return DecompositionResult(
            base: base,
            stacks: stacks,
            achieved: achieved,
            remainder: max(0, target - achieved),
            paired: paired,
            unit: unit
        )
    }
}
