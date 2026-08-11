import SwiftUI

/// A palette, loaded from `Resources/Themes/*.json`.
///
/// The chrome is glass and the page is paper: `stock` is always opaque and
/// matte, never a material. Toolbars and sheets get their translucency from the
/// system, not from here.
struct Theme: Identifiable, Hashable, Sendable, Codable {

    enum Appearance: String, Codable, Sendable, CaseIterable {
        case light
        case dark
    }

    struct Palette: Hashable, Sendable, Codable {
        /// The page. Opaque, always.
        var stock: HexColor
        var ink: HexColor
        var inkSecondary: HexColor
        var accent: HexColor
        /// A second ink, for themes built around two-colour printing. Falls
        /// back to `accent` when a theme doesn't declare one.
        var accentAlternate: HexColor?
        /// Ruled lines, grids, hairlines.
        var rule: HexColor
        /// The fore-edge strip body.
        var edge: HexColor
        /// The fore-edge highlight, and the locked-clasp glyph.
        var gilt: HexColor
    }

    var id: String
    var name: String
    var appearance: Appearance
    /// 0...1 paper-grain intensity. Zeroed under Increase Contrast and
    /// Reduce Transparency.
    var grain: Double
    var palette: Palette

    private enum CodingKeys: String, CodingKey {
        case id, name, appearance, grain, palette
    }
}

// MARK: - Token accessors
//
// View code reads these. It never touches `palette` members as HexColor and
// never converts a hex string itself.

extension Theme {
    var stock: Color { palette.stock.color }
    var ink: Color { palette.ink.color }
    var inkSecondary: Color { palette.inkSecondary.color }
    var accent: Color { palette.accent.color }
    var accentAlternate: Color { (palette.accentAlternate ?? palette.accent).color }
    var rule: Color { palette.rule.color }
    var edge: Color { palette.edge.color }
    var gilt: Color { palette.gilt.color }

    /// Ink at reduced weight, for placeholders and disabled affordances.
    var inkTertiary: Color { palette.inkSecondary.mixed(with: palette.stock, amount: 0.45).color }

    /// A fill that reads as pressed paper rather than a floating surface.
    var inset: Color { palette.stock.mixed(with: palette.ink, amount: 0.06).color }

    /// The tint applied to a checked item's label.
    var inkMuted: Color { palette.ink.mixed(with: palette.stock, amount: 0.55).color }

    var colorScheme: ColorScheme {
        appearance == .dark ? .dark : .light
    }
}

// MARK: - Accessibility resolution

extension Theme {
    /// Produces the palette actually used for rendering.
    ///
    /// Increase Contrast pushes ink and secondary ink away from the page,
    /// strengthens rules, and removes grain — grain is texture, and texture is
    /// noise to someone who turned that setting on. Reduce Transparency alone
    /// only removes grain.
    func resolved(increaseContrast: Bool, reduceTransparency: Bool) -> Theme {
        guard increaseContrast || reduceTransparency else { return self }

        var resolved = self
        if increaseContrast {
            let page = palette.stock
            resolved.palette.ink = palette.ink.pushedAway(from: page, by: 0.55)
            resolved.palette.inkSecondary = palette.inkSecondary.pushedAway(from: page, by: 0.45)
            resolved.palette.accent = palette.accent.pushedAway(from: page, by: 0.25)
            resolved.palette.accentAlternate = palette.accentAlternate?.pushedAway(from: page, by: 0.25)
            resolved.palette.rule = palette.rule.mixed(with: resolved.palette.ink, amount: 0.45)
        }
        resolved.grain = 0
        return resolved
    }
}

// MARK: - Fallback

extension Theme {
    /// Used only if the bundle's theme files are missing or unreadable, which
    /// would be a packaging failure. `ThemeLoaderTests` asserts the real files
    /// load, so this should never be reached in a shipped build.
    static let fallback = Theme(
        id: "fallback",
        name: "Fallback",
        appearance: .light,
        grain: 0,
        palette: Palette(
            stock: HexColor(red: 1, green: 1, blue: 1),
            ink: HexColor(red: 0, green: 0, blue: 0),
            inkSecondary: HexColor(red: 0.35, green: 0.35, blue: 0.35),
            accent: HexColor(red: 0, green: 0.32, blue: 0.6),
            accentAlternate: nil,
            rule: HexColor(red: 0.8, green: 0.8, blue: 0.8),
            edge: HexColor(red: 0.2, green: 0.2, blue: 0.2),
            gilt: HexColor(red: 0.55, green: 0.45, blue: 0.33)
        )
    )
}
