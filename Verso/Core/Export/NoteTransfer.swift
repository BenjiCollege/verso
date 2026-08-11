import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A note leaving the app by drag, drop or share.
///
/// Markdown rather than a link: a note dropped into Mail should arrive as
/// something the recipient can read, not as a URL that only resolves on the
/// device it came from.
struct NoteTransfer: Transferable, Sendable {

    var title: String
    var markdown: String

    @MainActor
    init(note: Note) {
        // Section 7's exclusions again. A locked note transfers its title and
        // nothing else — refusing outright would look like a bug, whereas an
        // empty note is obviously deliberate.
        let isShareable = VaultPolicy.isEligibleForSharing(note)
        self.title = VaultPolicy.listTitle(for: note)
        self.markdown = isShareable
            ? NoteExporter.markdown(for: note)
            : String(localized: "This note is locked.")
    }

    init(title: String, markdown: String) {
        self.title = title
        self.markdown = markdown
    }

    static var transferRepresentation: some TransferRepresentation {
        // Markdown first: a receiver that understands it gets structure, and
        // one that does not falls through to plain text with the same bytes.
        DataRepresentation(exportedContentType: UTType("net.daringfireball.markdown") ?? .plainText) { transfer in
            Data(transfer.markdown.utf8)
        }
        .suggestedFileName { transfer in
            let cleaned = transfer.title
                .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines))
                .joined(separator: "-")
                .trimmingCharacters(in: .whitespaces)
            return (cleaned.isEmpty ? "Note" : cleaned) + ".md"
        }

        ProxyRepresentation(exporting: \.markdown)
    }
}
