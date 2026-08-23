import CoreGraphics
import Foundation

/// A picture in a note.
///
/// The bytes live on disk under `assetID`, not in this payload. A photo
/// base64'd into the block's JSON would be re-encoded on every keystroke that
/// touches the note, carried whole in every version delta, and read into memory
/// by a list that only wanted the title.
struct ImagePayload: BlockPayload {
    static let blockType = BlockType.image

    var assetID: UUID?
    var caption: String
    /// Height in points at the page's width, measured when the image was
    /// imported. Stored so the page can reserve the right space before the
    /// bytes are read — without it a scroll position jumps as pictures load.
    var displayHeight: Double
    /// What the picture shows, for VoiceOver. A picture with no description is
    /// a hole in the note for anyone who cannot see it.
    var accessibilityDescription: String

    /// The page width to reserve a height against when the real one is not
    /// available.
    ///
    /// The editor knows how wide its column is; a share extension and a scan
    /// sheet do not, and neither can ask. Getting it wrong costs a slightly
    /// wrong reserved height until the block is next laid out — never a wrong
    /// picture — so one shared guess beats each caller inventing its own.
    static let assumedPageWidth: CGFloat = 320

    static let minimumHeight: Double = 80
    static let maximumHeight: Double = 1_200

    init(
        assetID: UUID? = nil,
        caption: String = "",
        displayHeight: Double = 240,
        accessibilityDescription: String = ""
    ) {
        self.assetID = assetID
        self.caption = caption
        self.displayHeight = min(max(displayHeight, Self.minimumHeight), Self.maximumHeight)
        self.accessibilityDescription = accessibilityDescription
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            assetID: try container.decodeIfPresent(UUID.self, forKey: .assetID),
            caption: try container.decodeIfPresent(String.self, forKey: .caption) ?? "",
            displayHeight: try container.decodeIfPresent(Double.self, forKey: .displayHeight) ?? 240,
            accessibilityDescription: try container.decodeIfPresent(
                String.self,
                forKey: .accessibilityDescription
            ) ?? ""
        )
    }

    static func makeDefault() -> ImagePayload {
        ImagePayload()
    }

    var isEmpty: Bool { assetID == nil }

    /// The caption, or the description, or nothing. Search and export both read
    /// this, and a picture with neither contributes no words — which is honest.
    var plainTextRepresentation: String {
        caption.isEmpty ? accessibilityDescription : caption
    }

    /// Markdown keeps the alt text, because that is the half of an image tag
    /// that survives being read aloud.
    var markdownRepresentation: String {
        let alt = accessibilityDescription.isEmpty ? caption : accessibilityDescription
        guard let assetID else { return "" }
        return "![\(alt)](\(assetID.uuidString).jpg)"
    }

    /// A template keeps the shape and drops the picture — someone else's photo
    /// is not part of a form.
    func resetForTemplate() -> ImagePayload {
        ImagePayload(displayHeight: displayHeight)
    }
}
