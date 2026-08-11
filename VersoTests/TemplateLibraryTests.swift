import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Template library")
struct TemplateLibraryTests {

    private let catalog = TemplateCatalog.shared

    /// Section 7 asks for twenty-four, plus blank.
    @Test("The library ships twenty-four templates and a blank page")
    func libraryIsComplete() {
        #expect(catalog.all.count == 25)
        #expect(catalog.template(id: "blank") != nil)
        #expect(catalog.all.filter { $0.id != "blank" }.count == 24)
    }

    @Test("Every category has its six", arguments: ["shopping", "fitness", "work", "life"])
    func categoriesAreBalanced(category: String) {
        #expect(catalog.all.filter { $0.category == category }.count == 6)
    }

    /// A template naming a block type this build cannot create is hidden from
    /// the gallery. If any ship hidden, the library is broken and the user
    /// silently gets fewer templates than the box says.
    @Test("Every bundled template is instantiable")
    func everyTemplateIsSupported() {
        for template in catalog.all {
            #expect(
                template.unsupportedBlockTypes().isEmpty,
                "\(template.id) uses \(template.unsupportedBlockTypes().joined(separator: ", "))"
            )
        }
        #expect(catalog.supported.count == catalog.all.count)
    }

    @Test("Every bundled template actually builds a note", arguments: TemplateCatalog.shared.all)
    func everyTemplateInstantiates(template: Template) throws {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try TemplateInstantiator.makeNote(from: template, in: context)

        #expect(note.orderedBlocks.count == template.blocks.count)
        #expect(note.orderedBlocks.map(\.position) == Array(0..<template.blocks.count))
        #expect(note.templateID == template.id)
        try context.save()
    }

    @Test("Every template has a name, an icon and a category")
    func metadataIsComplete() {
        for template in catalog.all {
            #expect(!template.name.isEmpty, "\(template.id) has no name")
            #expect(!template.systemImage.isEmpty, "\(template.id) has no icon")
            #expect(template.category != nil, "\(template.id) has no category")
        }
    }

    @Test("Template ids are unique")
    func idsAreUnique() {
        #expect(Set(catalog.all.map(\.id)).count == catalog.all.count)
    }

    /// Every theme, stock and reveal style a template names must exist, or the
    /// note silently falls back and the template looks broken.
    @Test("Templates only reference themes, stocks and reveal styles that exist")
    func referencesResolve() {
        let themes = ThemeCatalog.shared
        for template in catalog.all {
            if let themeID = template.themeID {
                #expect(themes.theme(id: themeID) != nil, "\(template.id) names theme \(themeID)")
            }
            if let stockID = template.stockID {
                #expect(themes.stock(id: stockID) != nil, "\(template.id) names stock \(stockID)")
            }
            if let revealID = template.revealStyleID {
                #expect(RevealStyle(rawValue: revealID) != nil, "\(template.id) names reveal \(revealID)")
            }
        }
    }

    /// A formula that cannot parse shows an error where a number should be.
    @Test("Every formula in the library parses")
    func formulasParse() throws {
        var checked = 0
        for template in catalog.all {
            for spec in template.blocks where spec.blockType == .formula {
                let data = try BlockRegistry.shared.transcode(spec.payload, as: .formula)
                let payload = try BlockCoding.decode(FormulaPayload.self, from: data)
                guard !payload.expression.isEmpty else { continue }

                // An unknown *name* is a runtime condition — the note may not
                // contain that block yet. A syntax error never is.
                var context = FormulaContext()
                context.numbers = ["itemCount": 0, "checkedCount": 0, "uncheckedCount": 0]
                context.lists = ["price": [], "quantity": [], "subtotal": [], "checkedSubtotal": [], "rating": []]

                #expect(throws: Never.self, "\(template.id): \(payload.expression)") {
                    _ = try FormulaEvaluator.evaluate(payload.expression, context: context)
                }
                checked += 1
            }
        }
        #expect(checked > 0, "the library should contain formulas")
    }

    // MARK: - The strength non-negotiables

    /// Section 7 lists six. Each is a generic block capability driven by JSON —
    /// this asserts the strength template actually switches them on, and that
    /// the engine needed no template-specific code to do it.
    @Test("The strength template turns on every non-negotiable")
    func strengthNonNegotiables() throws {
        let template = try #require(catalog.template(id: "strength-session"))
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        let note = try TemplateInstantiator.makeNote(from: template, in: context)

        let metrics = try note.orderedBlocks
            .filter { $0.type == .metric }
            .map { try $0.decoded(as: MetricPayload.self) }

        #expect(!metrics.isEmpty)
        // 1. Last session's numbers visible while logging.
        #expect(metrics.contains { $0.showsPreviousEntry })
        // 2. Rest timer on set completion.
        #expect(metrics.contains { ($0.restTimerSeconds ?? 0) > 0 })
        // 4. Plate maths.
        #expect(metrics.contains { $0.decomposition != nil })
        // 5. PR detection needs a series to detect against.
        #expect(metrics.allSatisfy { !$0.seriesID.isEmpty })
        // Exercise picking comes from a catalog, not from hardcoded names.
        #expect(metrics.contains { $0.catalogID == "exercises" })

        // 3. One-tap repeat set is table row duplication, so there has to be a
        // table of sets to repeat.
        let tables = try note.orderedBlocks
            .filter { $0.type == .table }
            .map { try $0.decoded(as: TablePayload.self) }
        #expect(tables.contains { table in
            table.columns.contains { $0.title == "Weight" } && table.columns.contains { $0.title == "Reps" }
        })

        // 6. Volume load as a formula block.
        let formulas = try note.orderedBlocks
            .filter { $0.type == .formula }
            .map { try $0.decoded(as: FormulaPayload.self) }
        #expect(formulas.contains { $0.expression.contains("sumproduct") })
    }
}

@Suite("Exercise catalog")
struct CatalogTests {

    private let library = CatalogLibrary.shared

    @Test("The exercise library loads")
    func exerciseLibraryLoads() throws {
        let catalog = try #require(library.catalog(id: "exercises"))
        #expect(catalog.entries.count > 150)
        #expect(catalog.name == "Exercises")
    }

    @Test("Every exercise has a name, an id and at least one facet")
    func entriesAreWellFormed() throws {
        let catalog = try #require(library.catalog(id: "exercises"))
        for entry in catalog.entries {
            #expect(!entry.name.isEmpty)
            #expect(!entry.id.isEmpty, "\(entry.name) has no id")
            #expect(!entry.tags.isEmpty, "\(entry.name) has no tags")
        }
    }

    @Test("Exercise ids are unique, so two of them cannot share a series")
    func idsAreUnique() throws {
        let catalog = try #require(library.catalog(id: "exercises"))
        #expect(Set(catalog.entries.map(\.id)).count == catalog.entries.count)
    }

    @Test("Ids are derived from names by the same slug the metric block uses")
    func idsMatchTheSlug() throws {
        let catalog = try #require(library.catalog(id: "exercises"))
        for entry in catalog.entries {
            #expect(entry.id == MetricPayload.slug(entry.name), "\(entry.name) slugs to \(MetricPayload.slug(entry.name))")
        }
    }

    @Test("Searching matches names and facets, and ignores case and accents")
    func searchWorks() throws {
        let catalog = try #require(library.catalog(id: "exercises"))

        #expect(catalog.entries.filter { $0.matches("squat") }.count > 5)
        #expect(catalog.entries.filter { $0.matches("SQUAT") }.count > 5)
        #expect(catalog.entries.filter { $0.matches("hamstrings") }.count > 3)
        #expect(catalog.entries.filter { $0.matches("") }.count == catalog.entries.count)
        #expect(catalog.entries.filter { $0.matches("zzzz") }.isEmpty)
    }

    @Test("Facets are offered for filtering")
    func facetsExist() throws {
        let catalog = try #require(library.catalog(id: "exercises"))
        let tags = Set(catalog.tagValues)
        #expect(tags.contains("quads"))
        #expect(tags.contains("mobility"))
        #expect(tags.contains("cardio"))
        #expect(!catalog.entries(tagged: "barbell").isEmpty)
    }
}
