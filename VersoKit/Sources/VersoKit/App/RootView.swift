import SwiftUI

/// Wires the environment once.
///
/// Theme, stock, catalogue and the reduce-motion resolver all enter here and
/// nowhere else. A view further down never resolves an accessibility setting or
/// reads a JSON file — it reads `\.theme` and `\.motion`.
struct RootView: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.colorScheme) private var systemColorScheme

    private let catalog = ThemeCatalog.shared

    var body: some View {
        LibraryView()
            .environment(\.themeCatalog, catalog)
            .versoTheme(
                appearance.theme(systemColorScheme: systemColorScheme, catalog: catalog),
                stock: appearance.stock(catalog: catalog),
                pinnedColorScheme: appearance.pinnedColorScheme(catalog: catalog)
            )
            .versoMotion()
    }
}
