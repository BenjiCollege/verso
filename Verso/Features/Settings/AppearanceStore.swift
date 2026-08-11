import Foundation
import SwiftUI

/// The user's theme and stock choice.
///
/// Deliberately not `@AppStorage`: the store is `@Observable` so a change in
/// Settings re-themes the whole app in one pass, and `UserDefaults` access is
/// declared in `PrivacyInfo.xcprivacy`.
@MainActor
@Observable
final class AppearanceStore {

    enum Mode: String, CaseIterable, Sendable {
        /// A light theme in light mode, a dark theme in dark mode.
        case followSystem
        /// One theme, whatever the system is doing.
        case pinned

        var displayName: LocalizedStringResource {
            switch self {
            case .followSystem: "Follow System"
            case .pinned: "Always"
            }
        }
    }

    private enum Key {
        static let mode = "appearance.mode"
        static let lightTheme = "appearance.theme.light"
        static let darkTheme = "appearance.theme.dark"
        static let pinnedTheme = "appearance.theme.pinned"
        static let stock = "appearance.stock"
        static let typewriter = "editor.typewriter"
        static let keepAudioOnDevice = "audio.localOnly"
    }

    private let defaults: UserDefaults

    var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: Key.mode) } }
    var lightThemeID: String { didSet { defaults.set(lightThemeID, forKey: Key.lightTheme) } }
    var darkThemeID: String { didSet { defaults.set(darkThemeID, forKey: Key.darkTheme) } }
    var pinnedThemeID: String { didSet { defaults.set(pinnedThemeID, forKey: Key.pinnedTheme) } }
    var stockID: String { didSet { defaults.set(stockID, forKey: Key.stock) } }

    /// Typewriter scroll holds the caret on a fixed line. Some people find the
    /// page moving under a stationary caret unsettling rather than calming, so
    /// it is a setting and it defaults to off.
    var isTypewriterEnabled: Bool { didSet { defaults.set(isTypewriterEnabled, forKey: Key.typewriter) } }

    /// The default for new recordings. Each one can still be changed
    /// afterwards; this is only what a fresh one starts as.
    var keepAudioOnDevice: Bool { didSet { defaults.set(keepAudioOnDevice, forKey: Key.keepAudioOnDevice) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isTypewriterEnabled = defaults.bool(forKey: Key.typewriter)
        self.keepAudioOnDevice = defaults.bool(forKey: Key.keepAudioOnDevice)
        self.mode = Mode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .followSystem
        self.lightThemeID = defaults.string(forKey: Key.lightTheme) ?? ThemeCatalog.defaultLightThemeID
        self.darkThemeID = defaults.string(forKey: Key.darkTheme) ?? ThemeCatalog.defaultDarkThemeID
        self.pinnedThemeID = defaults.string(forKey: Key.pinnedTheme) ?? ThemeCatalog.defaultLightThemeID
        self.stockID = defaults.string(forKey: Key.stock) ?? ThemeCatalog.defaultStockID
    }

    // MARK: - Resolution

    /// The app-wide theme. A note may still override it with its own `themeID`.
    func theme(systemColorScheme: ColorScheme, catalog: ThemeCatalog) -> Theme {
        switch mode {
        case .pinned:
            catalog.resolveTheme(selectedID: pinnedThemeID, appearance: .light)
        case .followSystem:
            systemColorScheme == .dark
                ? catalog.resolveTheme(selectedID: darkThemeID, appearance: .dark)
                : catalog.resolveTheme(selectedID: lightThemeID, appearance: .light)
        }
    }

    /// `nil` while following the system, so the system stays in charge.
    func pinnedColorScheme(catalog: ThemeCatalog) -> ColorScheme? {
        guard mode == .pinned else { return nil }
        return catalog.resolveTheme(selectedID: pinnedThemeID, appearance: .light).colorScheme
    }

    func stock(catalog: ThemeCatalog) -> Stock {
        catalog.resolveStock(selectedID: stockID)
    }

    /// Which slot a theme picker writes to for the current mode and appearance.
    func selectTheme(_ id: String, systemColorScheme: ColorScheme) {
        switch mode {
        case .pinned:
            pinnedThemeID = id
        case .followSystem:
            if systemColorScheme == .dark { darkThemeID = id } else { lightThemeID = id }
        }
    }

    func selectedThemeID(systemColorScheme: ColorScheme) -> String {
        switch mode {
        case .pinned: pinnedThemeID
        case .followSystem: systemColorScheme == .dark ? darkThemeID : lightThemeID
        }
    }
}
