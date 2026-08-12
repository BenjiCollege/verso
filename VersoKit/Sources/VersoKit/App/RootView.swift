import SwiftUI

/// Wires the environment once.
///
/// Theme, stock, catalogue and the reduce-motion resolver all enter here and
/// nowhere else. A view further down never resolves an accessibility setting or
/// reads a JSON file — it reads `\.theme` and `\.motion`.
struct RootView: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(HapticEngine.self) private var haptics
    @Environment(CustomThemeStore.self) private var customThemes
    @Environment(\.colorScheme) private var systemColorScheme

    /// Bundled themes plus the user's own, recomputed when the store changes —
    /// which is what makes a theme usable the moment it is saved rather than on
    /// the next launch. `ThemeCatalog.shared` stays the bundled set, for the
    /// exporters and the widgets, which have no user themes to read.
    private var catalog: ThemeCatalog {
        ThemeCatalog.shared.adding(customThemes.themes)
    }

    var body: some View {
        LibraryView()
            .environment(\.themeCatalog, catalog)
            .versoTheme(
                appearance.theme(systemColorScheme: systemColorScheme, catalog: catalog),
                stock: appearance.stock(catalog: catalog),
                colorScheme: appearance.appliedColorScheme(
                    systemColorScheme: systemColorScheme,
                    catalog: catalog
                )
            )
            .environment(\.readingPreferences, appearance.reading)
            // The engine is built once in the scene, so the preference is
            // pushed into it rather than read from it — nothing below here
            // should have to know a setting exists to stay silent.
            .onChange(of: appearance.isHapticsEnabled, initial: true) { _, enabled in
                haptics.isEnabled = enabled
            }
            .versoMotion()
    }
}
