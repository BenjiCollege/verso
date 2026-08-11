import Foundation

/// A list of named things a block can offer as a picker.
///
/// The exercise library is one of these. So could a list of ingredients, or of
/// currencies, or of anything else. The engine knows how to show a catalog and
/// how to turn a chosen entry into a label and a series id; it does not know
/// what is in one, and adding another is a JSON file and no Swift.
struct Catalog: Identifiable, Hashable, Sendable, Codable {

    struct Entry: Identifiable, Hashable, Sendable, Codable {
        var id: String
        var name: String
        /// Free-form facets. The exercise library uses these for muscle groups;
        /// nothing in the engine reads their meaning, only their text.
        var tags: [String]
        /// One line, shown under the name. Form notes, for the exercises.
        var notes: String?
        /// Overrides the unit of the metric that selects this entry.
        var unit: String?

        init(id: String, name: String, tags: [String] = [], notes: String? = nil, unit: String? = nil) {
            self.id = id
            self.name = name
            self.tags = tags
            self.notes = notes
            self.unit = unit
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? MetricPayload.slug(name)
            self.name = name
            self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
            self.unit = try container.decodeIfPresent(String.self, forKey: .unit)
        }

        func matches(_ query: String) -> Bool {
            guard !query.isEmpty else { return true }
            let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            func contains(_ text: String) -> Bool {
                text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
            }
            return contains(name) || tags.contains(where: contains)
        }
    }

    var id: String
    var name: String
    var entries: [Entry]

    private enum CodingKeys: String, CodingKey {
        case id, name, entries
    }

    func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Facet values in first-appearance order, for grouping the picker.
    var tagValues: [String] {
        var seen = Set<String>()
        return entries.flatMap(\.tags).filter { seen.insert($0).inserted }
    }

    func entries(tagged tag: String) -> [Entry] {
        entries.filter { $0.tags.contains(tag) }
    }
}

/// Every catalog in the bundle.
struct CatalogLibrary: Sendable {
    let catalogs: [Catalog]

    static func load(from bundle: Bundle = .module) -> CatalogLibrary {
        CatalogLibrary(
            catalogs: BundleResourceLoader.loadAll(
                Catalog.self,
                kind: "catalog",
                subdirectory: "Exercises",
                in: bundle
            )
        )
    }

    static let shared = CatalogLibrary.load()

    func catalog(id: String?) -> Catalog? {
        guard let id else { return nil }
        return catalogs.first { $0.id == id }
    }
}
