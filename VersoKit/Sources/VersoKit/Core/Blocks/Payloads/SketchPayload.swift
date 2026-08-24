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
    /// Whatever handwriting recognition last read off this drawing.
    ///
    /// A search key, never content. It is deliberately not shown anywhere and
    /// not exported as prose: recognition is a guess, the ink is the record,
    /// and a note that quietly replaced what someone wrote with what a model
    /// thought they wrote would be worse than one that could not be searched.
    var recognisedText: String

    static let minimumHeight: Double = 180
    static let maximumHeight: Double = 1_200

    init(
        drawing: Data = Data(),
        height: Double = minimumHeight,
        recordedWith: UUID? = nil,
        recognisedText: String = ""
    ) {
        self.drawing = drawing
        self.height = min(max(height, Self.minimumHeight), Self.maximumHeight)
        self.recordedWith = recordedWith
        self.recognisedText = recognisedText
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            drawing: try container.decodeIfPresent(Data.self, forKey: .drawing) ?? Data(),
            height: try container.decodeIfPresent(Double.self, forKey: .height) ?? Self.minimumHeight,
            recordedWith: try container.decodeIfPresent(UUID.self, forKey: .recordedWith),
            // Absent in every sketch saved before handwriting was readable.
            // Those notes stay searchable-as-nothing until they are next drawn
            // on, which is the same position they were already in.
            recognisedText: try container.decodeIfPresent(String.self, forKey: .recognisedText) ?? ""
        )
    }

    static func makeDefault() -> SketchPayload {
        SketchPayload()
    }

    var isEmpty: Bool { drawing.isEmpty }

    /// What the drawing contributes to search, Spotlight and the index.
    ///
    /// This one property is the whole feature: `BlockRegistry` funnels it into
    /// `SemanticIndex`, `SpotlightIndexer` and `IntelligenceProvider`, so
    /// returning real words here makes handwriting findable everywhere without
    /// a line of change in any of them.
    ///
    /// Falls back to "Sketch" only when nothing could be read, so a diagram
    /// still says what it is.
    var plainTextRepresentation: String {
        guard !isEmpty else { return "" }
        return recognisedText.isEmpty ? String(localized: "Sketch") : recognisedText
    }

    var markdownRepresentation: String {
        isEmpty ? "" : "_\(String(localized: "Sketch"))_"
    }

    /// Saved as a template, a sketch keeps its size and loses its ink — and
    /// with the ink, anything that was read out of it.
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
