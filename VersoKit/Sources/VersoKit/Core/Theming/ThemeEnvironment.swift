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
    /// Always set, and always the theme's own appearance.
    ///
    /// Leaving it to the system — which is what following the system used to
    /// mean — let the paper and the chrome disagree: a dark theme with iOS in
    /// Light gave dark ink on dark paper, and the note read as empty. The theme
    /// is the single source of appearance now, and `AppearanceStore` guarantees
    /// the value it hands over matches the theme it selected, so this cannot
    /// feed back into that choice.
    let colorScheme: ColorScheme

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
            // The chrome is glass and takes its cue from the colour scheme, so
            // the theme has to set it or a light theme leaves dark toolbars
            // behind — and, worse, dark body text on light paper.
            .preferredColorScheme(colorScheme)
            .environment(\.colorScheme, colorScheme)
            .tint(resolved.accent)
    }
}

extension View {
    /// The colour scheme defaults to the theme's own, which is what every caller
    /// wants: a themed surface should never be lit by someone else's decision.
    func versoTheme(_ theme: Theme, stock: Stock, colorScheme: ColorScheme? = nil) -> some View {
        modifier(ThemeApplier(theme: theme, stock: stock, colorScheme: colorScheme ?? theme.colorScheme))
    }
}
