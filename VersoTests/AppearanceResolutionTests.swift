import Foundation
import SwiftUI
import Testing
@testable import VersoKit

/// The invariant a shipped build broke: the paper and the chrome must agree.
///
/// A theme decides the paper. Every system-derived colour — `.secondary`, glass
/// toolbars, a sheet's background, a `TextField`'s default ink — follows the
/// colour scheme. When those two disagree you get dark ink on dark paper, and
/// the note reads as blank. The editor was passing `preferredColorScheme(nil)`
/// for any note without a theme of its own, which cancelled the app's choice and
/// handed appearance back to iOS mid-navigation.
@Suite("Appearance resolution")
@MainActor
struct AppearanceResolutionTests {

    private let catalog = ThemeCatalog.shared

    private func makeStore() throws -> AppearanceStore {
        let defaults = try #require(UserDefaults(suiteName: "verso.tests.\(UUID().uuidString)"))
        return AppearanceStore(defaults: defaults)
    }

    /// The one that matters. Whatever the mode, whatever the system is doing,
    /// the scheme the app renders in is the scheme its theme was built for.
    @Test(
        "The applied colour scheme always matches the resolved theme",
        arguments: [ColorScheme.light, .dark]
    )
    func schemeAlwaysMatchesTheme(system: ColorScheme) throws {
        for theme in catalog.themes {
            for mode in AppearanceStore.Mode.allCases {
                let store = try makeStore()
                store.mode = mode
                store.selectTheme(theme.id, systemColorScheme: system, catalog: catalog)

                let resolved = store.theme(systemColorScheme: system, catalog: catalog)
                let applied = store.appliedColorScheme(systemColorScheme: system, catalog: catalog)

                #expect(
                    applied == resolved.colorScheme,
                    "\(theme.id) in \(mode) under \(system) renders \(applied) on \(resolved.appearance) paper"
                )
            }
        }
    }

    @Test("Choosing a theme built for the other appearance makes the app follow it")
    func mismatchedChoiceStopsFollowingTheSystem() throws {
        let store = try makeStore()
        store.mode = .followSystem

        let dark = try #require(catalog.themes.first { $0.appearance == .dark })
        store.selectTheme(dark.id, systemColorScheme: .light, catalog: catalog)

        #expect(store.mode == .pinned, "the tap chose a look, not a light-mode slot")
        #expect(store.theme(systemColorScheme: .light, catalog: catalog).id == dark.id)
        #expect(store.appliedColorScheme(systemColorScheme: .light, catalog: catalog) == .dark)
    }

    @Test("Choosing a theme built for the current appearance keeps following the system")
    func matchedChoiceKeepsFollowing() throws {
        let store = try makeStore()
        store.mode = .followSystem

        let light = try #require(catalog.themes.first { $0.appearance == .light })
        store.selectTheme(light.id, systemColorScheme: .light, catalog: catalog)

        #expect(store.mode == .followSystem)
        #expect(store.theme(systemColorScheme: .light, catalog: catalog).id == light.id)
    }

    /// An earlier build could write a dark theme into the light slot. That data
    /// is still on people's phones, so resolution has to correct it rather than
    /// render it.
    @Test("A theme stored in the wrong slot is corrected, not rendered")
    func wrongSlotIsCorrected() throws {
        let store = try makeStore()
        store.mode = .followSystem
        let dark = try #require(catalog.themes.first { $0.appearance == .dark })
        store.lightThemeID = dark.id

        let resolved = store.theme(systemColorScheme: .light, catalog: catalog)
        #expect(resolved.appearance == .light)
    }

    @Test("An unknown theme id falls back to something legible")
    func unknownIDFallsBack() throws {
        let store = try makeStore()
        store.mode = .pinned
        store.pinnedThemeID = "a-theme-that-was-deleted"

        let resolved = store.theme(systemColorScheme: .dark, catalog: catalog)
        #expect(catalog.themes.contains { $0.id == resolved.id })
        #expect(store.appliedColorScheme(systemColorScheme: .dark, catalog: catalog) == resolved.colorScheme)
    }
}
