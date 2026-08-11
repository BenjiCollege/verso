import Foundation
import SwiftUI

/// The loaded set of themes and stocks.
///
/// Adding a theme is one JSON file in `Resources/Themes/` and no Swift at all.
/// Nothing outside this type and `BundleResourceLoader` reads a theme file.
struct ThemeCatalog: Sendable {

    let themes: [Theme]
    let stocks: [Stock]

    static let defaultLightThemeID = "iron-gall"
    static let defaultDarkThemeID = "midnight-oil"
    static let defaultStockID = "ruled"

    init(themes: [Theme], stocks: [Stock]) {
        // Presentation order is by name so a new theme file slots in
        // alphabetically rather than wherever the filesystem put it.
        self.themes = themes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.stocks = stocks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func load(from bundle: Bundle = .module) -> ThemeCatalog {
        ThemeCatalog(
            themes: BundleResourceLoader.loadAll(Theme.self, kind: "theme", subdirectory: "Themes", in: bundle),
            stocks: BundleResourceLoader.loadAll(Stock.self, kind: "stock", subdirectory: "Stocks", in: bundle)
        )
    }

    static let shared = ThemeCatalog.load()

    // MARK: - Lookup

    func theme(id: String?) -> Theme? {
        guard let id else { return nil }
        return themes.first { $0.id == id }
    }

    func stock(id: String?) -> Stock? {
        guard let id else { return nil }
        return stocks.first { $0.id == id }
    }

    func themes(for appearance: Theme.Appearance) -> [Theme] {
        themes.filter { $0.appearance == appearance }
    }

    /// The theme to use when nothing has been chosen, or when the chosen one
    /// no longer exists because its file was removed.
    func defaultTheme(for appearance: Theme.Appearance) -> Theme {
        let preferredID = appearance == .dark ? Self.defaultDarkThemeID : Self.defaultLightThemeID
        return theme(id: preferredID)
            ?? themes(for: appearance).first
            ?? themes.first
            ?? .fallback
    }

    func defaultStock() -> Stock {
        stock(id: Self.defaultStockID) ?? stocks.first ?? .plain
    }

    /// Resolves the theme for a given selection, falling back cleanly if the id
    /// is stale. `nil` selection means "follow the system appearance".
    func resolveTheme(selectedID: String?, appearance: Theme.Appearance) -> Theme {
        theme(id: selectedID) ?? defaultTheme(for: appearance)
    }

    func resolveStock(selectedID: String?) -> Stock {
        stock(id: selectedID) ?? defaultStock()
    }
}
