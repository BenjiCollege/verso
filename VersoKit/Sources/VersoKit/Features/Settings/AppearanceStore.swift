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
        static let textScale = "reading.textScale"
        static let lineSpacingScale = "reading.lineSpacing"
        static let marginScale = "reading.margin"
        static let typeface = "reading.typeface"
        static let hapticsEnabled = "editor.haptics"
        static let autocorrect = "editor.autocorrect"
        static let focusMode = "editor.focusMode"
        static let hasSeenGallery = "onboarding.gallerySeen"
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

    // MARK: - Reading

    var textScale: Double {
        didSet { defaults.set(textScale, forKey: Key.textScale) }
    }
    var lineSpacingScale: Double {
        didSet { defaults.set(lineSpacingScale, forKey: Key.lineSpacingScale) }
    }
    var marginScale: Double {
        didSet { defaults.set(marginScale, forKey: Key.marginScale) }
    }
    var typeface: ContentTypeface {
        didSet { defaults.set(typeface.rawValue, forKey: Key.typeface) }
    }

    /// What every themed surface reads to size its type.
    var reading: ReadingPreferences {
        ReadingPreferences(
            textScale: textScale,
            lineSpacingScale: lineSpacingScale,
            marginScale: marginScale,
            typeface: typeface
        )
    }

    func resetReading() {
        textScale = ReadingPreferences.default.textScale
        lineSpacingScale = ReadingPreferences.default.lineSpacingScale
        marginScale = ReadingPreferences.default.marginScale
        typeface = ReadingPreferences.default.typeface
    }

    // MARK: - Editor behaviour

    var isHapticsEnabled: Bool { didSet { defaults.set(isHapticsEnabled, forKey: Key.hapticsEnabled) } }
    var isAutocorrectEnabled: Bool { didSet { defaults.set(isAutocorrectEnabled, forKey: Key.autocorrect) } }

    /// Whether the page dims everything but the sentence being written. A
    /// preference rather than a per-session toggle, so it survives relaunch.
    var isFocusModeEnabled: Bool { didSet { defaults.set(isFocusModeEnabled, forKey: Key.focusMode) } }

    /// Whether the template gallery has been shown unprompted.
    ///
    /// A first launch used to be an empty list and a `+`, which describes
    /// nothing. The gallery is the best answer the app has to "what is this
    /// for", and it was one level down. Shown once, and never again in the way
    /// that would make it a nag.
    var hasSeenGallery: Bool { didSet { defaults.set(hasSeenGallery, forKey: Key.hasSeenGallery) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isTypewriterEnabled = defaults.bool(forKey: Key.typewriter)
        self.keepAudioOnDevice = defaults.bool(forKey: Key.keepAudioOnDevice)

        // `object(forKey:)` rather than `double(forKey:)`: the latter answers 0
        // for a key never written, and a text scale of zero is an invisible app.
        func stored(_ key: String, default fallback: Double, in range: ClosedRange<Double>) -> Double {
            guard let value = defaults.object(forKey: key) as? Double else { return fallback }
            return min(max(value, range.lowerBound), range.upperBound)
        }

        self.textScale = stored(Key.textScale, default: 1, in: ReadingPreferences.textScaleRange)
        self.lineSpacingScale = stored(Key.lineSpacingScale, default: 1, in: ReadingPreferences.lineSpacingRange)
        self.marginScale = stored(Key.marginScale, default: 1, in: ReadingPreferences.marginRange)
        self.typeface = ContentTypeface(rawValue: defaults.string(forKey: Key.typeface) ?? "") ?? .serif

        // These three default to on, so the same trick: absent is not false.
        self.isHapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        self.isAutocorrectEnabled = defaults.object(forKey: Key.autocorrect) as? Bool ?? true
        self.isFocusModeEnabled = defaults.bool(forKey: Key.focusMode)
        self.hasSeenGallery = defaults.bool(forKey: Key.hasSeenGallery)
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
            return catalog.theme(id: pinnedThemeID)
                ?? catalog.defaultTheme(for: systemColorScheme == .dark ? .dark : .light)
        case .followSystem:
            let wanted: Theme.Appearance = systemColorScheme == .dark ? .dark : .light
            let stored = catalog.theme(id: wanted == .dark ? darkThemeID : lightThemeID)
            // The appearance is checked rather than assumed. A dark theme
            // sitting in the light slot — which is what an earlier build wrote
            // when you picked one — paints dark paper while the scheme below
            // says light, and the ink vanishes into the page.
            guard let stored, stored.appearance == wanted else {
                return catalog.defaultTheme(for: wanted)
            }
            return stored
        }
    }

    /// What the whole app renders as, chrome included.
    ///
    /// Always the theme's own appearance, never the system's. The theme decides
    /// the paper, and every system-derived colour — `.secondary`, toolbar glass,
    /// a sheet's background, a `TextField`'s default ink — has to agree with it
    /// or the text disappears into it.
    ///
    /// This cannot feed back on itself: in `followSystem` the theme above always
    /// matches the appearance that selected it, so forcing that appearance
    /// changes nothing and the next pass resolves identically.
    func appliedColorScheme(systemColorScheme: ColorScheme, catalog: ThemeCatalog) -> ColorScheme {
        theme(systemColorScheme: systemColorScheme, catalog: catalog).colorScheme
    }

    func stock(catalog: ThemeCatalog) -> Stock {
        catalog.resolveStock(selectedID: stockID)
    }

    /// Which slot a theme picker writes to for the current mode and appearance.
    ///
    /// Choosing a theme whose appearance disagrees with the system — a dark
    /// paper while iOS is in Light — is read as choosing the look, so the app
    /// adopts it and stops following the system. The alternative is storing a
    /// dark theme in the light slot, where it is either ignored or renders
    /// unreadably, and neither is what the tap meant.
    func selectTheme(_ id: String, systemColorScheme: ColorScheme, catalog: ThemeCatalog) {
        guard let theme = catalog.theme(id: id) else { return }
        let systemAppearance: Theme.Appearance = systemColorScheme == .dark ? .dark : .light

        switch mode {
        case .pinned:
            pinnedThemeID = id
        case .followSystem where theme.appearance == systemAppearance:
            if systemAppearance == .dark { darkThemeID = id } else { lightThemeID = id }
        case .followSystem:
            pinnedThemeID = id
            mode = .pinned
        }
    }

    func selectedThemeID(systemColorScheme: ColorScheme) -> String {
        switch mode {
        case .pinned: pinnedThemeID
        case .followSystem: systemColorScheme == .dark ? darkThemeID : lightThemeID
        }
    }
}
