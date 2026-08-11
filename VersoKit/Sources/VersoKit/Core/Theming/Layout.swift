import SwiftUI

/// Spacing, radius and measure tokens.
///
/// Every gap, inset and corner in `Features/` comes from here. A bare number in
/// a `.padding()` is the same bug as a hex literal.
enum Layout {

    // MARK: - Spacing scale

    /// A four-point scale. Nothing sits between two steps; if a layout seems to
    /// need 10pt, it needs 8 or 12.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let cosy: CGFloat = 12
        static let regular: CGFloat = 16
        static let loose: CGFloat = 24
        static let airy: CGFloat = 32
        static let vast: CGFloat = 48
    }

    // MARK: - Rules and radii

    static let hairline: CGFloat = 0.5

    enum Radius {
        static let tight: CGFloat = 6
        static let regular: CGFloat = 12
        static let loose: CGFloat = 20
        static let capsule: CGFloat = 999
    }

    // MARK: - The page

    /// Horizontal breathing room between the measure and the page edge on a
    /// compact-width device.
    static let pageMargin: CGFloat = Space.loose

    /// Room reserved at the leading edge for the fore-edge strip, which lands
    /// in Phase 6. Reserved now so the measure doesn't shift when it appears.
    static let foreEdgeWidth: CGFloat = 14

    /// The target measure, in characters. Section 6 caps it at 68.
    static let measureCharacters: CGFloat = 68

    /// Mean glyph advance as a fraction of point size for New York at text
    /// sizes. Used to turn a character count into a width.
    static let meanGlyphAdvance: CGFloat = 0.48

    /// Width of `measureCharacters` at the given point size. On iPhone this is
    /// wider than the screen and has no effect; on iPad it is what stops the
    /// page stretching to fill the window.
    static func measureWidth(atPointSize size: CGFloat) -> CGFloat {
        measureCharacters * meanGlyphAdvance * size
    }

    // MARK: - Controls

    /// Minimum tappable edge. Below this, VoiceOver and Switch Control users
    /// start missing targets.
    static let minimumHitTarget: CGFloat = 44

    static let checkboxSize: CGFloat = 22
}
