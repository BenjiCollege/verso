import SwiftUI

/// Paper stock, loaded from `Resources/Stocks/*.json`.
///
/// A stock is a set of drawing parameters, not a named look. `legal` is ruled
/// paper that happens to have a margin rule; `ledger` is a grid that happens to
/// tint alternate rows. Any stock combines with any theme, so nothing here
/// carries a colour — colours come from the active `Theme`.
struct Stock: Identifiable, Hashable, Sendable, Codable {

    /// The drawing primitive. Everything else is a parameter on top of it.
    enum Pattern: String, Codable, Sendable, CaseIterable {
        case none
        case horizontalRules
        case dots
        case grid
    }

    /// A single vertical rule, as on legal pads.
    struct MarginRule: Hashable, Sendable, Codable {
        /// Distance from the leading edge, in points.
        var inset: Double
        var width: Double
        var opacity: Double
        /// Draw in the accent colour rather than the rule colour.
        var usesAccent: Bool
    }

    var id: String
    var name: String
    var pattern: Pattern

    /// Spacing between rules or grid lines, as a multiple of the body line
    /// height. 1.0 puts one rule under every line of text.
    var spacingMultiple: Double
    var lineWidth: Double
    var opacity: Double
    /// Radius of a dot in a dot-grid, in points. Ignored by other patterns.
    var dotRadius: Double

    var marginRule: MarginRule?
    /// Manuscript paper: a lighter guide line at the x-height of each row.
    var showsBaselineGuides: Bool
    /// Ledger paper: alternate rows get a faint wash. 0 disables.
    var alternateRowTint: Double

    private enum CodingKeys: String, CodingKey {
        case id, name, pattern, spacingMultiple, lineWidth, opacity, dotRadius
        case marginRule, showsBaselineGuides, alternateRowTint
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        let rawPattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? Pattern.none.rawValue
        self.pattern = Pattern(rawValue: rawPattern) ?? .none
        self.spacingMultiple = try container.decodeIfPresent(Double.self, forKey: .spacingMultiple) ?? 1
        self.lineWidth = try container.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 0.5
        self.opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        self.dotRadius = try container.decodeIfPresent(Double.self, forKey: .dotRadius) ?? 0
        self.marginRule = try container.decodeIfPresent(MarginRule.self, forKey: .marginRule)
        self.showsBaselineGuides = try container.decodeIfPresent(Bool.self, forKey: .showsBaselineGuides) ?? false
        self.alternateRowTint = try container.decodeIfPresent(Double.self, forKey: .alternateRowTint) ?? 0
    }

    init(
        id: String,
        name: String,
        pattern: Pattern = .none,
        spacingMultiple: Double = 1,
        lineWidth: Double = 0.5,
        opacity: Double = 1,
        dotRadius: Double = 0,
        marginRule: MarginRule? = nil,
        showsBaselineGuides: Bool = false,
        alternateRowTint: Double = 0
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.spacingMultiple = spacingMultiple
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.dotRadius = dotRadius
        self.marginRule = marginRule
        self.showsBaselineGuides = showsBaselineGuides
        self.alternateRowTint = alternateRowTint
    }

    /// Nothing drawn. Used when the bundle is unreadable.
    static let plain = Stock(id: "plain", name: "Plain", pattern: .none)
}
