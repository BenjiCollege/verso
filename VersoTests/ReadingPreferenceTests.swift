import Foundation
import Testing
import UIKit
@testable import VersoKit

/// The reading controls have to reach the prose.
///
/// Three of the four moved nothing on the page. Size, typeface and line spacing
/// all had a consumer inside `VersoTextStyle` — which chrome, headings and
/// captions go through — and no consumer at all in `AttributedText`, which is
/// what actually renders a text block. So dragging Size grew every heading in
/// the app and left the writing alone, and picking Mono restyled the toolbar.
///
/// These assert the join. They are cheap and they would all have failed before.
@Suite("Reading preferences reach the prose")
struct ReadingPreferenceTests {

    private let theme = ThemeCatalog.shared.theme(id: "iron-gall") ?? .fallback
    private let size: CGFloat = 17

    private func prose(_ text: String = "Hello") -> NSAttributedString {
        NSAttributedString(string: text)
    }

    private func font(of rendered: NSAttributedString, at index: Int = 0) throws -> UIFont {
        try #require(rendered.attribute(.font, at: index, effectiveRange: nil) as? UIFont)
    }

    private func paragraph(of rendered: NSAttributedString) throws -> NSParagraphStyle {
        try #require(rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
    }

    // MARK: - Typeface

    @Test("Each typeface renders prose in a different family")
    func typefaceReachesProse() throws {
        var names: Set<String> = []

        for face in ContentTypeface.allCases {
            let rendered = AttributedText.rendered(
                prose(),
                theme: theme,
                bodySize: size,
                reading: ReadingPreferences(typeface: face)
            )
            names.insert(try font(of: rendered).fontName)
        }

        // Three faces, three fonts. Before, all three produced New York.
        #expect(names.count == ContentTypeface.allCases.count)
    }

    /// The face marks prose, not code. A code run is monospaced because that is
    /// what tells you it is code — a reader choosing Serif has not asked for
    /// their code samples to be set in New York.
    @Test("A code run stays monospaced whatever the reader picked")
    func codeIgnoresTypeface() throws {
        let code = NSMutableAttributedString(string: "let x = 1")
        code.addAttribute(
            VersoTextAttribute.inlineStyle,
            value: NSNumber(value: InlineStyle.code.rawValue),
            range: NSRange(location: 0, length: code.length)
        )

        for face in ContentTypeface.allCases {
            let rendered = AttributedText.rendered(
                code,
                theme: theme,
                bodySize: size,
                reading: ReadingPreferences(typeface: face)
            )
            let name = try font(of: rendered).fontName
            #expect(
                name.localizedCaseInsensitiveContains("mono"),
                "\(face) rendered code as \(name)"
            )
        }
    }

    // MARK: - Line spacing

    @Test("The reader's line spacing reaches the prose")
    func lineSpacingReachesProse() throws {
        let tight = AttributedText.rendered(
            prose(), theme: theme, bodySize: size,
            reading: ReadingPreferences(lineSpacingScale: 0.85)
        )
        let loose = AttributedText.rendered(
            prose(), theme: theme, bodySize: size,
            reading: ReadingPreferences(lineSpacingScale: 1.5)
        )

        let tightMultiple = try paragraph(of: tight).lineHeightMultiple
        let looseMultiple = try paragraph(of: loose).lineHeightMultiple

        #expect(tightMultiple < looseMultiple)
        #expect(tightMultiple == Typography.Role.body.lineHeightMultiple * 0.85)
        #expect(looseMultiple == Typography.Role.body.lineHeightMultiple * 1.5)
    }

    /// The one that protects the whole idea of the app.
    ///
    /// Ruled paper only means something while the writing sits on the rules.
    /// `PageBackground` spaces its rules by `Typography.contentLineHeight` and
    /// TextKit lays the text out by the paragraph style — if those two ever
    /// disagree, every line drifts off the paper it is printed on, and the
    /// further down the page the worse it gets.
    @Test("Ruled lines and prose are laid out at the same leading", arguments: [0.85, 1.0, 1.25, 1.5])
    func rulesFollowTheProse(scale: Double) throws {
        let reading = ReadingPreferences(lineSpacingScale: scale)

        let rendered = AttributedText.rendered(prose(), theme: theme, bodySize: size, reading: reading)
        let proseLineHeight = try paragraph(of: rendered).lineHeightMultiple * size
        let ruleSpacing = Typography.contentLineHeight(forSize: size, reading: reading)

        #expect(proseLineHeight == ruleSpacing)
    }

    // MARK: - Size

    @Test("Body size reaches the prose")
    func sizeReachesProse() throws {
        let small = AttributedText.rendered(prose(), theme: theme, bodySize: 14, reading: .default)
        let large = AttributedText.rendered(prose(), theme: theme, bodySize: 24, reading: .default)

        #expect(try font(of: small).pointSize == 14)
        #expect(try font(of: large).pointSize == 24)
    }

    /// Typing attributes come from the same place, so the character you type
    /// next matches the paragraph it lands in rather than snapping when the
    /// block re-renders.
    @Test("What you type next matches what is already there")
    func typingAttributesAgreeWithRendering() throws {
        let reading = ReadingPreferences(lineSpacingScale: 1.3, typeface: .mono)

        let rendered = AttributedText.rendered(prose(), theme: theme, bodySize: size, reading: reading)
        let typing = AttributedText.typingAttributes(
            style: [], theme: theme, bodySize: size, reading: reading
        )

        let typedFont = try #require(typing[.font] as? UIFont)
        let typedParagraph = try #require(typing[.paragraphStyle] as? NSParagraphStyle)

        #expect(typedFont.fontName == (try font(of: rendered).fontName))
        #expect(typedParagraph.lineHeightMultiple == (try paragraph(of: rendered).lineHeightMultiple))
    }
}
