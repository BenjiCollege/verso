import Foundation
import Testing
@testable import VersoKit

/// User themes are files, like user templates, so that adding one needs no
/// schema change. These cover the parts that would silently lose someone's work.
@Suite("Custom themes")
@MainActor
struct CustomThemeStoreTests {

    private func makeStore() -> CustomThemeStore {
        let directory = URL.temporaryDirectory.appending(path: "verso-themes-\(UUID().uuidString)")
        return CustomThemeStore(directory: directory)
    }

    private var base: Theme {
        ThemeCatalog.shared.resolveTheme(selectedID: nil, appearance: .light)
    }

    @Test("A saved theme comes back, with the same colours")
    func saveAndReload() {
        let store = makeStore()
        var draft = store.draft(basedOn: base)
        draft.name = "Marginalia"

        #expect(store.save(draft))
        #expect(store.themes.count == 1)

        let saved = store.themes[0]
        #expect(saved.name == "Marginalia")
        #expect(saved.palette == draft.palette)
        #expect(saved.appearance == draft.appearance)
    }

    @Test("A draft is a copy, never the original under a new name")
    func draftIsIndependent() {
        let store = makeStore()
        let draft = store.draft(basedOn: base)

        #expect(draft.id != base.id)
        #expect(draft.isCustom)
        #expect(!base.isCustom, "a bundled theme is never custom")
        #expect(draft.palette == base.palette, "it starts as what it was copied from")
    }

    @Test("Saving twice makes two themes, not one overwritten")
    func eachSaveIsItsOwnTheme() {
        let store = makeStore()
        #expect(store.save(store.draft(basedOn: base)))
        #expect(store.save(store.draft(basedOn: base)))
        #expect(store.themes.count == 2)
    }

    @Test("Editing a saved theme replaces it rather than duplicating it")
    func editingKeepsOneCopy() {
        let store = makeStore()
        var draft = store.draft(basedOn: base)
        #expect(store.save(draft))

        draft.name = "Renamed"
        #expect(store.save(draft))

        #expect(store.themes.count == 1)
        #expect(store.themes[0].name == "Renamed")
    }

    @Test("Deleting removes it")
    func delete() {
        let store = makeStore()
        let draft = store.draft(basedOn: base)
        #expect(store.save(draft))
        store.delete(id: store.themes[0].id)
        #expect(store.themes.isEmpty)
    }

    @Test("A custom theme joins the catalogue and resolves by id")
    func catalogueIncludesCustomThemes() {
        let store = makeStore()
        var draft = store.draft(basedOn: base)
        draft.name = "Marginalia"
        #expect(store.save(draft))

        let combined = ThemeCatalog.shared.adding(store.themes)
        let id = store.themes[0].id

        #expect(combined.theme(id: id)?.name == "Marginalia")
        #expect(combined.themes.count == ThemeCatalog.shared.themes.count + 1)
        // And it can be chosen for its appearance, like any other.
        #expect(combined.themes(for: draft.appearance).contains { $0.id == id })
    }
}
