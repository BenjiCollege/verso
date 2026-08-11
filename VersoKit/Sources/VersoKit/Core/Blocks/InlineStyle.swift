import Foundation

/// The inline marks a run of text can carry.
///
/// These are *semantic*. A bold run stores "bold", not a font; a linked run
/// stores a note id, not a colour. Presentation is resolved at display time by
/// `AttributedText.rendered(_:theme:bodySize:)`, which is what lets a theme
/// switch re-ink existing notes instead of leaving last week's colours baked
/// into the archive.
struct InlineStyle: OptionSet, Hashable, Sendable, Codable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let bold = InlineStyle(rawValue: 1 << 0)
    static let italic = InlineStyle(rawValue: 1 << 1)
    static let underline = InlineStyle(rawValue: 1 << 2)
    static let strikethrough = InlineStyle(rawValue: 1 << 3)
    static let code = InlineStyle(rawValue: 1 << 4)

    static let all: [InlineStyle] = [.bold, .italic, .underline, .strikethrough, .code]

    var displayName: LocalizedStringResource {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .code: "Code"
        default: "Formatting"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        default: "textformat"
        }
    }
}

/// Attribute keys written into the archived `NSAttributedString`.
///
/// Values are deliberately `NSNumber` and `NSString`: the payload is archived
/// with `requiringSecureCoding: true`, and those bridge cleanly. A custom class
/// here would need its own `NSSecureCoding` conformance and would break every
/// note written before it existed.
enum VersoTextAttribute {
    /// `NSNumber` wrapping `InlineStyle.rawValue`.
    static let inlineStyle = NSAttributedString.Key("versoInlineStyle")

    /// `NSString` holding the target `Note.id` UUID string.
    static let noteLink = NSAttributedString.Key("versoNoteLink")

    /// Every key this app owns. Used when stripping semantics from a paste.
    static let all: [NSAttributedString.Key] = [inlineStyle, noteLink]

    /// Keys derived from semantics at display time. Stripped before archiving —
    /// storing them would freeze the current theme into the note.
    static let presentation: [NSAttributedString.Key] = [
        .font,
        .foregroundColor,
        .backgroundColor,
        .underlineStyle,
        .underlineColor,
        .strikethroughStyle,
        .strikethroughColor,
        .paragraphStyle,
        .kern,
        .tracking,
    ]
}
