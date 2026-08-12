import Foundation
import OSLog
import SwiftUI

/// Themes the user made, as files.
///
/// Files in Application Support rather than a `@Model`, for the same reason
/// user templates are: a theme is a document, storing it as one means export and
/// import are the bytes already on disk, and it needs no schema change — which
/// would be yours to approve.
///
/// The cost is honest and worth naming: these do not sync. A theme made on the
/// phone stays on the phone.
@MainActor
@Observable
final class CustomThemeStore {

    static let logger = Logger(subsystem: "com.verso.notes", category: "themes")
    static let fileExtension = "versotheme"

    /// The prefix every user theme's id carries, so a bundled theme and a made
    /// one can never collide and `isCustom` needs no separate flag on disk.
    static let idPrefix = "custom."

    private(set) var themes: [Theme] = []
    private(set) var lastError: String?

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "Themes", directoryHint: .isDirectory)
        reload()
    }

    // MARK: - Reading

    func reload() {
        guard FileManager.default.fileExists(atPath: directory.path()) else {
            themes = []
            return
        }

        let decoder = JSONDecoder()
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

        themes = urls
            .filter { $0.pathExtension == Self.fileExtension }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let theme = try? decoder.decode(Theme.self, from: data)
                else {
                    // One unreadable file must not cost the user the rest.
                    Self.logger.error("Skipping unreadable theme at \(url.lastPathComponent, privacy: .public)")
                    return nil
                }
                return theme
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Writing

    @discardableResult
    func save(_ theme: Theme) -> Bool {
        var theme = theme
        if !theme.id.hasPrefix(Self.idPrefix) {
            theme.id = Self.idPrefix + UUID().uuidString
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(theme).write(to: url(for: theme.id), options: .atomic)
            lastError = nil
            reload()
            return true
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("Could not save theme: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func delete(id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
        reload()
    }

    /// A copy of an existing theme, as the starting point for a new one.
    ///
    /// Starting from a working theme rather than from black-on-white is what
    /// makes this usable: seven colours chosen from nothing is a design job,
    /// and adjusting two of an existing seven is an afternoon's whim.
    func draft(basedOn theme: Theme) -> Theme {
        var draft = theme
        draft.id = Self.idPrefix + UUID().uuidString
        draft.name = String(localized: "\(theme.name) Copy")
        return draft
    }

    private func url(for id: String) -> URL {
        // The id is a UUID behind a known prefix, so there is nothing in it a
        // filename would object to.
        directory.appending(path: "\(id).\(Self.fileExtension)")
    }
}

extension Theme {
    var isCustom: Bool { id.hasPrefix(CustomThemeStore.idPrefix) }
}

extension ThemeCatalog {
    /// The bundled catalogue plus the user's own.
    ///
    /// A made theme with the id of a bundled one cannot happen — the prefix
    /// rules it out — so this is a concatenation rather than a merge.
    func adding(_ extra: [Theme]) -> ThemeCatalog {
        ThemeCatalog(themes: themes + extra, stocks: stocks)
    }
}
