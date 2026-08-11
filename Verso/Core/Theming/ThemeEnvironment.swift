import SwiftUI

extension EnvironmentValues {
    /// The palette in force, already resolved for Increase Contrast and Reduce
    /// Transparency. View code reads this and nothing else.
    @Entry var theme: Theme = .fallback

    /// The paper the page is printed on.
    @Entry var stock: Stock = .plain

    /// Everything available to choose from, for pickers.
    @Entry var themeCatalog: ThemeCatalog = .shared
}

/// Resolves accessibility settings once, at the point the theme enters the
/// environment, so no view further down has to remember to check them.
private struct ThemeApplier: ViewModifier {
    let theme: Theme
    let stock: Stock

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let resolved = theme.resolved(
            increaseContrast: contrast == .increased,
            reduceTransparency: reduceTransparency
        )

        content
            .environment(\.theme, resolved)
            .environment(\.stock, stock)
            // The chrome is glass and takes its cue from the system colour
            // scheme, so a light theme must not leave dark toolbars behind.
            .preferredColorScheme(resolved.colorScheme)
            .tint(resolved.accent)
    }
}

extension View {
    func versoTheme(_ theme: Theme, stock: Stock) -> some View {
        modifier(ThemeApplier(theme: theme, stock: stock))
    }
}
