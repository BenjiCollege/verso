import Foundation
import OSLog

/// Templates the user made, stored as files.
///
/// Files rather than a `@Model`, for two reasons. One: export and import are
/// then the same bytes that are already on disk, so sharing a template is a
/// file changing hands and nothing else — no server, per section 1. Two:
/// adding a model is a schema change, and those are yours to approve.
///
/// The cost is that user templates do not sync through iCloud. If they should,
/// that is a `UserTemplate` model and a migration — see the README.
@MainActor
@Observable
final class UserTemplateStore {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "templates")
    static let fileExtension = "versotemplate"

    private(set) var templates: [Template] = []
    private(set) var lastError: String?

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        reload()
    }

    private static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appending(path: "UserTemplates", directoryHint: .isDirectory)
    }

    // MARK: - Reading

    func reload() {
        guard FileManager.default.fileExists(atPath: directory.path()) else {
            templates = []
            return
        }

        let decoder = JSONDecoder()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        templates = urls
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      var template = try? decoder.decode(Template.self, from: data)
                else {
                    // One unreadable file must not cost the user the rest of
                    // their templates.
                    Self.logger.error("Skipping unreadable template at \(url.lastPathComponent, privacy: .public)")
                    return nil
                }
                template.isUserAuthored = true
                return template
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Writing

    @discardableResult
    func save(_ template: Template) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encode(template).write(to: url(for: template.id), options: .atomic)
            lastError = nil
            reload()
            return true
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Could not save template: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func delete(id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
        reload()
    }

    func rename(id: String, to name: String) {
        guard var template = templates.first(where: { $0.id == id }) else { return }
        template.name = name
        save(template)
    }

    // MARK: - Export and import

    /// Bytes for a `ShareLink` or a file export.
    func exportData(for template: Template) throws -> Data {
        try encode(template)
    }

    /// Writes to a temporary file so `ShareLink` and drag-and-drop have
    /// something with a sensible filename to hand over.
    func exportFile(for template: Template) throws -> URL {
        let url = URL.temporaryDirectory
            .appending(path: sanitised(template.name))
            .appendingPathExtension(Self.fileExtension)
        try encode(template).write(to: url, options: .atomic)
        return url
    }

    /// Imports a template file. A new id is minted so importing the same file
    /// twice, or a file that clashes with a bundled template, never silently
    /// overwrites anything.
    @discardableResult
    func importTemplate(from url: URL) -> Template? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            return importTemplate(from: data)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func importTemplate(from data: Data) -> Template? {
        do {
            var template = try JSONDecoder().decode(Template.self, from: data)
            template.id = "user." + UUID().uuidString
            template.isUserAuthored = true
            guard save(template) else { return nil }
            return template
        } catch {
            lastError = String(localized: "That doesn't look like a Verso template.")
            Self.logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Private

    private func encode(_ template: Template) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(template)
    }

    private func url(for id: String) -> URL {
        directory
            .appending(path: sanitised(id))
            .appendingPathExtension(Self.fileExtension)
    }

    /// Template names come from the user and end up as filenames.
    private func sanitised(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? UUID().uuidString : String(cleaned.prefix(100))
    }
}
