import Foundation
import OSLog

/// The loaded template library.
///
/// Templates whose block types this build can't create are kept out of
/// `supported` and logged, so the gallery never offers a note it can't make.
struct TemplateCatalog: Sendable {

    static let logger = Logger(subsystem: "com.verso.notes", category: "templates")

    /// Every template that parsed, including ones this build can't instantiate.
    let all: [Template]

    init(all: [Template]) {
        self.all = all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func load(from bundle: Bundle = .main) -> TemplateCatalog {
        let catalog = TemplateCatalog(
            all: BundleResourceLoader.loadAll(Template.self, kind: "template", subdirectory: "Templates", in: bundle)
        )
        for template in catalog.all {
            let unsupported = template.unsupportedBlockTypes()
            if !unsupported.isEmpty {
                logger.notice(
                    "Template \(template.id, privacy: .public) hidden; unsupported block types: \(unsupported.joined(separator: ", "), privacy: .public)"
                )
            }
        }
        return catalog
    }

    static let shared = TemplateCatalog.load()

    /// What the gallery shows.
    var supported: [Template] {
        all.filter(\.isSupported)
    }

    func template(id: String?) -> Template? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// The template used when a note is created without choosing one.
    var blank: Template {
        template(id: "blank") ?? Template(id: "blank", name: "Blank", systemImage: "doc")
    }

    /// Category keys in first-appearance order, for gallery sections.
    var categories: [String] {
        var seen = Set<String>()
        return supported.compactMap(\.category).filter { seen.insert($0).inserted }
    }

    func templates(in category: String) -> [Template] {
        supported.filter { $0.category == category }
    }
}
