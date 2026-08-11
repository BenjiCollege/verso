import Foundation

/// A drawing.
///
/// The `PKDrawing` is stored as its own archive rather than being re-encoded,
/// because that archive carries per-point timestamps — which is what makes ink
/// replayable alongside audio at all.
struct SketchPayload: BlockPayload {
    static let blockType = BlockType.sketch

    var drawing: Data
    /// Points. Grows as the drawing does, so the block does not have to be
    /// resized by hand.
    var height: Double
    /// Set when the drawing was made while a recording was running, so replay
    /// knows to reveal it stroke by stroke.
    var recordedWith: UUID?

    static let minimumHeight: Double = 180
    static let maximumHeight: Double = 1_200

    init(drawing: Data = Data(), height: Double = minimumHeight, recordedWith: UUID? = nil) {
        self.drawing = drawing
        self.height = min(max(height, Self.minimumHeight), Self.maximumHeight)
        self.recordedWith = recordedWith
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            drawing: try container.decodeIfPresent(Data.self, forKey: .drawing) ?? Data(),
            height: try container.decodeIfPresent(Double.self, forKey: .height) ?? Self.minimumHeight,
            recordedWith: try container.decodeIfPresent(UUID.self, forKey: .recordedWith)
        )
    }

    static func makeDefault() -> SketchPayload {
        SketchPayload()
    }

    var isEmpty: Bool { drawing.isEmpty }

    /// A drawing has no words. Saying so beats an empty line in an export.
    var plainTextRepresentation: String {
        isEmpty ? "" : String(localized: "Sketch")
    }

    var markdownRepresentation: String {
        isEmpty ? "" : "_\(String(localized: "Sketch"))_"
    }

    /// Saved as a template, a sketch keeps its size and loses its ink.
    func resetForTemplate() -> SketchPayload {
        SketchPayload(drawing: Data(), height: height)
    }
}

/// A recording attached to a note.
struct AudioPayload: BlockPayload {
    static let blockType = BlockType.audio

    /// Matches `AudioAsset.id`.
    var assetID: UUID?
    var label: String

    init(assetID: UUID? = nil, label: String = "") {
        self.assetID = assetID
        self.label = label
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            assetID: try container.decodeIfPresent(UUID.self, forKey: .assetID),
            label: try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        )
    }

    static func makeDefault() -> AudioPayload {
        AudioPayload()
    }

    var plainTextRepresentation: String { label }

    var markdownRepresentation: String {
        // A recording cannot come along to a Markdown file, and pretending
        // otherwise with a dead link would be worse than saying so.
        let name = label.isEmpty ? String(localized: "Recording") : label
        return "_\(name) — \(String(localized: "audio, not included in this export"))_"
    }

    /// A template carries the shape of a note, not somebody's voice.
    func resetForTemplate() -> AudioPayload {
        AudioPayload(assetID: nil, label: label)
    }
}
