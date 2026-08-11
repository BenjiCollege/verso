import Foundation
import OSLog

/// Finds and decodes the package's JSON resources.
///
/// This is the only type that reads JSON off disk. Themes, stocks, templates
/// and catalogues all come through here; nothing else opens a file.
///
/// It reads `Bundle.module`, which is what made extracting the package worth
/// doing on its own: SwiftPM's `.process` keeps the resource folders intact, so
/// a subdirectory lookup simply works. The previous version had to scan the
/// whole bundle and filter on a `"kind"` discriminator, because Xcode's
/// synchronized file groups may or may not preserve a folder when they copy it.
///
/// The `"kind"` field is still written in every file — it costs nothing, it
/// documents what a file is to anyone reading it, and it is what an imported
/// user template is identified by.
enum BundleResourceLoader {

    static let logger = Logger(subsystem: "com.verso.notes", category: "resources")

    /// Decodes every resource in a directory, skipping — and logging — any
    /// individual file that fails rather than losing the whole catalogue to one
    /// bad character.
    static func loadAll<T: Decodable>(
        _ type: T.Type,
        kind: String,
        subdirectory: String,
        in bundle: Bundle = .module
    ) -> [T] {
        let decoder = JSONDecoder()
        var results: [T] = []

        for url in candidateURLs(subdirectory: subdirectory, in: bundle) {
            do {
                let data = try Data(contentsOf: url)
                results.append(try decoder.decode(T.self, from: data))
            } catch {
                logger.error(
                    "Skipping \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        if results.isEmpty {
            logger.fault("No \(kind, privacy: .public) resources found in \(bundle.bundleIdentifier ?? "the bundle", privacy: .public).")
        }
        return results
    }

    /// Sorted by filename so the load order is stable, which is what makes a
    /// duplicate-id tiebreak deterministic across devices.
    private static func candidateURLs(subdirectory: String, in bundle: Bundle) -> [URL] {
        let scoped = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? []
        guard scoped.isEmpty else {
            return scoped.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        // A flat fallback, kept for the one case it still covers: a resource
        // added without a folder, or a bundle laid out differently than
        // expected.
        return (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Where the haptic patterns live. Same bundle, different extension.
    static func url(forResource name: String, extension ext: String, subdirectory: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: ext)
    }
}
