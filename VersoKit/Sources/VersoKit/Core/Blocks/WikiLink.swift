import Foundation

/// `[[Wiki link]]` parsing.
///
/// The brackets stay in the text rather than being hidden behind an attachment.
/// That keeps Markdown export honest, keeps the link editable with ordinary
/// text editing, and means a note opened on a build that has never heard of
/// links still reads correctly.
///
/// The resolved target is carried alongside as a `noteLink` attribute, so a
/// link survives the target being renamed. The title in the brackets is what a
/// human reads; the attribute is what the app follows.
enum WikiLink {

    static let openingDelimiter = "[["
    static let closingDelimiter = "]]"

    struct Match: Hashable, Sendable {
        /// The text between the brackets, trimmed.
        var title: String
        /// The whole `[[…]]` span, including both delimiters.
        var range: NSRange
    }

    /// A link the user is still typing: an unclosed `[[` before the caret.
    struct Draft: Hashable, Sendable {
        /// The `[[` and everything typed after it, up to the caret.
        var range: NSRange
        /// What has been typed so far, which is the autocomplete query.
        var query: String
    }

    private static let regex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\[\[([^\[\]\n]*)\]\]"#
    )

    /// Every completed link in the text.
    static func matches(in text: String) -> [Match] {
        guard let regex else { return [] }
        let ns = text as NSString
        return regex
            .matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { result in
                guard result.numberOfRanges > 1 else { return nil }
                let title = ns.substring(with: result.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                return Match(title: title, range: result.range)
            }
    }

    static func titles(in text: String) -> [String] {
        matches(in: text).map(\.title)
    }

    /// Finds an unclosed `[[` immediately governing the caret.
    ///
    /// Scans backwards for `[[`, giving up at a newline or at a `]]`, so a
    /// caret sitting after a finished link doesn't reopen it.
    /// Works in UTF-16 offsets throughout, because that is what `UITextView`
    /// selections and `NSRange` speak. Counting `Character`s here would drift
    /// on any note containing an emoji.
    static func draft(in text: String, caret: Int) -> Draft? {
        let ns = text as NSString
        guard caret >= 2, caret <= ns.length else { return nil }

        let newline = ("\n" as UnicodeScalar).value
        let open = ("[" as UnicodeScalar).value
        let close = ("]" as UnicodeScalar).value

        var index = caret - 1
        while index >= 1 {
            let current = UInt32(ns.character(at: index))
            let previous = UInt32(ns.character(at: index - 1))

            if current == newline { return nil }
            // A closing pair between here and the caret means the nearest `[[`
            // already belongs to a finished link.
            if previous == close && current == close { return nil }
            if previous == open && current == open {
                let start = index - 1
                let query = ns.substring(with: NSRange(location: index + 1, length: caret - index - 1))
                if query.contains("]") { return nil }
                return Draft(
                    range: NSRange(location: start, length: caret - start),
                    query: query.trimmingCharacters(in: .whitespaces)
                )
            }
            index -= 1
        }
        return nil
    }

    /// The text to substitute for a chosen suggestion, caret-ready.
    static func markup(for title: String) -> String {
        openingDelimiter + title + closingDelimiter
    }
}
