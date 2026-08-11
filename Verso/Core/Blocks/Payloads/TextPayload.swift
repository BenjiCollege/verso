import Foundation

/// A paragraph of rich text.
///
/// The rich representation is stored as an archived `NSAttributedString` rather
/// than a `Codable` `AttributedString`, because archiving carries the platform
/// attribute scopes (fonts, colours, paragraph styles, link and attachment
/// attributes) that the Phase 2 TextKit 2 editor will actually produce, with no
/// per-attribute coding configuration to keep in sync.
///
/// `plain` is a denormalised mirror. It exists so note previews, titling and
/// search never have to unarchive; it is rewritten on every mutation and is
/// never the source of truth.
struct TextPayload: BlockPayload {
    static let blockType = BlockType.text

    var archive: Data
    var plain: String

    init(archive: Data, plain: String) {
        self.archive = archive
        self.plain = plain
    }

    init(_ attributed: AttributedString) {
        let ns = NSAttributedString(attributed)
        self.archive = (try? NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: true)) ?? Data()
        self.plain = ns.string
    }

    init(plain: String) {
        self.init(AttributedString(plain))
    }

    static func makeDefault() -> TextPayload {
        TextPayload(plain: "")
    }

    var plainTextRepresentation: String { plain }

    /// Falls back to `plain` if the archive is empty or unreadable, so a
    /// corrupt or forward-versioned attribute run degrades to legible text
    /// rather than an empty paragraph.
    var attributed: AttributedString {
        guard !archive.isEmpty,
              let ns = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: archive)
        else {
            return AttributedString(plain)
        }
        return AttributedString(ns)
    }

    var isEmpty: Bool {
        plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
