import SwiftUI
import UIKit

/// Converts between the two forms a run of text takes: the semantic form that
/// gets archived, and the presented form the text view displays.
///
/// Nothing else in the app applies a font or an ink colour to text. That is the
/// whole point — a theme change re-runs `rendered` and the note is re-inked,
/// and no view has to know how bold is spelled in UIKit.
enum AttributedText {

    // MARK: - Semantics

    /// Strips every derived presentation attribute, keeping only the marks the
    /// user actually made. Call this before archiving.
    static func semantic(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let full = NSRange(location: 0, length: result.length)
        for key in VersoTextAttribute.presentation {
            result.removeAttribute(key, range: full)
        }
        // Pasted content arrives carrying whatever the source app used. Its
        // semantics are translated on paste; anything left is not ours.
        result.removeAttribute(.link, range: full)
        result.removeAttribute(.shadow, range: full)
        result.removeAttribute(.attachment, range: full)
        return result
    }

    /// Reads the inline marks that apply across an entire range. A style is
    /// reported only if every character carries it, which is what makes a
    /// toolbar button show as "on" honestly for a mixed selection.
    static func style(of text: NSAttributedString, in range: NSRange) -> InlineStyle {
        guard range.length > 0, range.upperBound <= text.length else {
            return style(at: max(0, range.location - 1), in: text)
        }

        var common: InlineStyle?
        text.enumerateAttribute(VersoTextAttribute.inlineStyle, in: range) { value, _, _ in
            let style = InlineStyle(rawValue: (value as? NSNumber)?.intValue ?? 0)
            common = common.map { $0.intersection(style) } ?? style
        }
        return common ?? []
    }

    private static func style(at index: Int, in text: NSAttributedString) -> InlineStyle {
        guard text.length > 0, index >= 0, index < text.length else { return [] }
        let value = text.attribute(VersoTextAttribute.inlineStyle, at: index, effectiveRange: nil)
        return InlineStyle(rawValue: (value as? NSNumber)?.intValue ?? 0)
    }

    /// Applies or removes a mark across a range.
    static func setting(
        _ style: InlineStyle,
        enabled: Bool,
        in range: NSRange,
        of text: NSAttributedString
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        guard range.length > 0, range.upperBound <= result.length else { return result }

        result.enumerateAttribute(VersoTextAttribute.inlineStyle, in: range) { value, subrange, _ in
            var current = InlineStyle(rawValue: (value as? NSNumber)?.intValue ?? 0)
            if enabled { current.insert(style) } else { current.remove(style) }

            if current.isEmpty {
                result.removeAttribute(VersoTextAttribute.inlineStyle, range: subrange)
            } else {
                result.addAttribute(
                    VersoTextAttribute.inlineStyle,
                    value: NSNumber(value: current.rawValue),
                    range: subrange
                )
            }
        }
        return result
    }

    static func noteLink(of text: NSAttributedString, at index: Int) -> UUID? {
        guard index >= 0, index < text.length else { return nil }
        let value = text.attribute(VersoTextAttribute.noteLink, at: index, effectiveRange: nil)
        return (value as? String).flatMap(UUID.init(uuidString:))
    }

    // MARK: - Presentation

    /// Resolves semantics into fonts, colours and paragraph geometry for the
    /// active theme and the current Dynamic Type size.
    static func rendered(
        _ text: NSAttributedString,
        theme: Theme,
        bodySize: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let full = NSRange(location: 0, length: result.length)

        result.addAttributes(
            [
                .font: font(for: [], size: bodySize),
                .foregroundColor: UIColor(theme.ink),
                .paragraphStyle: paragraphStyle(bodySize: bodySize),
            ],
            range: full
        )

        result.enumerateAttribute(VersoTextAttribute.inlineStyle, in: full) { value, range, _ in
            let style = InlineStyle(rawValue: (value as? NSNumber)?.intValue ?? 0)
            guard !style.isEmpty else { return }

            result.addAttribute(.font, value: font(for: style, size: bodySize), range: range)

            if style.contains(.underline) {
                result.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: UIColor(theme.ink),
                ], range: range)
            }
            if style.contains(.strikethrough) {
                result.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: UIColor(theme.inkSecondary),
                ], range: range)
            }
            if style.contains(.code) {
                result.addAttributes([
                    .foregroundColor: UIColor(theme.inkSecondary),
                    .backgroundColor: UIColor(theme.inset),
                ], range: range)
            }
        }

        // Links are drawn last so their ink wins over a code run's.
        result.enumerateAttribute(VersoTextAttribute.noteLink, in: full) { value, range, _ in
            guard value != nil else { return }
            result.addAttributes([
                .foregroundColor: UIColor(theme.accent),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: UIColor(theme.accent.opacity(0.4)),
            ], range: range)
        }

        return result
    }

    /// The attributes a freshly typed character takes.
    static func typingAttributes(
        style: InlineStyle,
        theme: Theme,
        bodySize: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: style, size: bodySize),
            .foregroundColor: UIColor(style.contains(.code) ? theme.inkSecondary : theme.ink),
            .paragraphStyle: paragraphStyle(bodySize: bodySize),
        ]
        if !style.isEmpty {
            attributes[VersoTextAttribute.inlineStyle] = NSNumber(value: style.rawValue)
        }
        if style.contains(.underline) {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    // MARK: - Fonts

    /// New York for prose, SF Mono for code, with bold and italic applied as
    /// symbolic traits so the family's own cuts are used rather than a synthetic
    /// slant.
    static func font(for style: InlineStyle, size: CGFloat) -> UIFont {
        let base: UIFont
        if style.contains(.code) {
            base = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        } else if let serif = UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) {
            base = UIFont(descriptor: serif, size: size)
        } else {
            base = UIFont.systemFont(ofSize: size)
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if style.contains(.bold) { traits.insert(.traitBold) }
        if style.contains(.italic) { traits.insert(.traitItalic) }
        guard !traits.isEmpty,
              let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        else { return base }

        return UIFont(descriptor: descriptor, size: size)
    }

    static func paragraphStyle(bodySize: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Typography.Role.body.lineHeightMultiple
        style.paragraphSpacing = bodySize * 0.35
        return style
    }
}
