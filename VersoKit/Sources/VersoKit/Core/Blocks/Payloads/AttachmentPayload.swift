import Foundation

/// A document attached to a note.
///
/// Section 5 describes the payload as a *file ref* and a page count, and that
/// is taken literally: the document itself lives in the app container and the
/// payload points at it. A small first-page thumbnail rides along so the block
/// still shows what it is on a device that does not have the file — see the
/// README for what it would take to make documents sync.
struct AttachmentPayload: BlockPayload {
    static let blockType = BlockType.attachment

    /// Names the file in the container.
    var assetID: UUID?
    var fileName: String
    var pageCount: Int
    var byteCount: Int
    /// JPEG of the first page. Small on purpose — this is in the block payload,
    /// which is read whenever the note is.
    var thumbnail: Data
    var annotations: DocumentAnnotations

    static let maximumThumbnailBytes = 60_000

    init(
        assetID: UUID? = nil,
        fileName: String = "",
        pageCount: Int = 0,
        byteCount: Int = 0,
        thumbnail: Data = Data(),
        annotations: DocumentAnnotations = DocumentAnnotations()
    ) {
        self.assetID = assetID
        self.fileName = fileName
        self.pageCount = max(0, pageCount)
        self.byteCount = max(0, byteCount)
        self.thumbnail = thumbnail
        self.annotations = annotations
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            assetID: try container.decodeIfPresent(UUID.self, forKey: .assetID),
            fileName: try container.decodeIfPresent(String.self, forKey: .fileName) ?? "",
            pageCount: try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 0,
            byteCount: try container.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0,
            thumbnail: try container.decodeIfPresent(Data.self, forKey: .thumbnail) ?? Data(),
            annotations: try container.decodeIfPresent(DocumentAnnotations.self, forKey: .annotations)
                ?? DocumentAnnotations()
        )
    }

    static func makeDefault() -> AttachmentPayload {
        AttachmentPayload()
    }

    var isEmpty: Bool { assetID == nil }

    var displayName: String {
        fileName.isEmpty ? String(localized: "Document") : fileName
    }

    var sizeDescription: String {
        ByteCountFormatStyle(style: .file).format(Int64(byteCount))
    }

    /// Highlighted passages are the part of a document that belongs to the
    /// note, so they are what search and export see.
    var plainTextRepresentation: String {
        ([displayName] + annotations.highlightedText).joined(separator: "\n")
    }

    var markdownRepresentation: String {
        var lines = ["**\(displayName)** — \(pageCount) \(pageCount == 1 ? "page" : "pages"), \(sizeDescription)"]
        for passage in annotations.highlightedText {
            lines.append("> \(passage)")
        }
        return lines.joined(separator: "\n\n")
    }

    /// A template carries the shape of a note, not somebody's document.
    func resetForTemplate() -> AttachmentPayload {
        AttachmentPayload(fileName: fileName)
    }
}
