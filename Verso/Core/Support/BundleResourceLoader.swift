import Foundation
import OSLog

/// Finds and decodes the app's JSON resources.
///
/// Every bundled JSON resource carries a `"kind"` discriminator. That is
/// deliberate belt-and-braces: Xcode's synchronized file groups add a resource
/// folder's contents to the bundle without necessarily preserving the folder,
/// so looking up by subdirectory alone is not reliable. This loader tries the
/// subdirectory first and falls back to scanning the bundle and filtering by
/// kind, which works either way.
///
/// This is the only type that reads JSON off disk. Themes, stocks and templates
/// all come through here; nothing else opens a file.
enum BundleResourceLoader {

    static let logger = Logger(subsystem: "com.verso.notes", category: "resources")

    private struct KindProbe: Decodable {
        let kind: String
    }

    /// Decodes every resource of the given kind, skipping — and logging — any
    /// individual file that fails rather than losing the whole catalog to one
    /// bad character.
    static func loadAll<T: Decodable>(
        _ type: T.Type,
        kind: String,
        subdirectory: String,
        in bundle: Bundle = .main
    ) -> [T] {
        let decoder = JSONDecoder()
        var results: [T] = []

        for url in candidateURLs(kind: kind, subdirectory: subdirectory, in: bundle) {
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
            logger.fault("No \(kind, privacy: .public) resources found in bundle.")
        }
        return results
    }

    private static func candidateURLs(kind: String, subdirectory: String, in bundle: Bundle) -> [URL] {
        if let scoped = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory), !scoped.isEmpty {
            return scoped.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        let all = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let decoder = JSONDecoder()
        return all
            .filter { url in
                guard let data = try? Data(contentsOf: url),
                      let probe = try? decoder.decode(KindProbe.self, from: data)
                else { return false }
                return probe.kind == kind
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
