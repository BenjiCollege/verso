import Foundation

/// The complete vocabulary of block types.
///
/// The full list lives here from day one even though Phase 1 only implements
/// five of them, so that `typeRaw` values written by a later build decode to a
/// known case rather than falling off a cliff. `BlockRegistry.isImplemented`
/// is the runtime authority on what this build can actually render.
enum BlockType: String, CaseIterable, Codable, Sendable {
    case text
    case heading
    case checklist
    case list
    case metric
    case timer
    case table
    case place
    case schedule
    case formula
    case progress
    case rating
    case callout
    case code
    case divider
    case image
    case sketch
    case audio
    case attachment
    case link
}

extension BlockType {
    /// User-facing name, shown in the block inserter. Deliberately generic —
    /// the engine names capabilities, never use cases.
    var displayName: LocalizedStringResource {
        switch self {
        case .text: "Text"
        case .heading: "Heading"
        case .checklist: "Checklist"
        case .list: "List"
        case .metric: "Metric"
        case .timer: "Timer"
        case .table: "Table"
        case .place: "Place"
        case .schedule: "Schedule"
        case .formula: "Formula"
        case .progress: "Progress"
        case .rating: "Rating"
        case .callout: "Callout"
        case .code: "Code"
        case .divider: "Divider"
        case .image: "Image"
        case .sketch: "Sketch"
        case .audio: "Audio"
        case .attachment: "Attachment"
        case .link: "Link"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .heading: "textformat.size"
        case .checklist: "checklist"
        case .list: "list.bullet"
        case .metric: "number"
        case .timer: "timer"
        case .table: "tablecells"
        case .place: "mappin.and.ellipse"
        case .schedule: "calendar"
        case .formula: "function"
        case .progress: "chart.bar.fill"
        case .rating: "star"
        case .callout: "exclamationmark.bubble"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        case .image: "photo"
        case .sketch: "scribble"
        case .audio: "waveform"
        case .attachment: "paperclip"
        case .link: "link"
        }
    }
}
