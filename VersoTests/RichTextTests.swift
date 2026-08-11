import Foundation
import Testing
import UIKit
@testable import VersoKit

@Suite("Inline styles and archiving")
struct InlineStyleTests {

    private func styled(_ string: String, _ style: InlineStyle) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: style.isEmpty ? [:] : [VersoTextAttribute.inlineStyle: NSNumber(value: style.rawValue)]
        )
    }

    @Test("Marks survive an archive round-trip through TextPayload")
    func marksSurviveArchiving() throws {
        let text = NSMutableAttributedString(string: "plain bold plain")
        text.addAttribute(
            VersoTextAttribute.inlineStyle,
            value: NSNumber(value: InlineStyle([.bold, .italic]).rawValue),
            range: NSRange(location: 6, length: 4)
        )

        let payload = TextPayload(semantic: text)
        let restored = payload.attributedNS

        #expect(restored.string == "plain bold plain")
        #expect(AttributedText.style(of: restored, in: NSRange(location: 6, length: 4)) == [.bold, .italic])
        #expect(AttributedText.style(of: restored, in: NSRange(location: 0, length: 5)) == [])
        #expect(payload.plain == "plain bold plain")
    }

    @Test("A note link survives archiving")
    func noteLinkSurvivesArchiving() throws {
        let target = UUID()
        let text = NSMutableAttributedString(string: "see [[Ledger]]")
        text.addAttribute(
            VersoTextAttribute.noteLink,
            value: target.uuidString,
            range: NSRange(location: 4, length: 10)
        )

        let restored = TextPayload(semantic: text).attributedNS
        #expect(AttributedText.noteLink(of: restored, at: 6) == target)
        #expect(AttributedText.noteLink(of: restored, at: 0) == nil)
    }

    /// The whole reason semantics are stored and presentation is not: a theme
    /// change has to re-ink existing notes.
    @Test("Presentation attributes are stripped before archiving")
    func presentationIsNotArchived() throws {
        let text = NSMutableAttributedString(string: "inked")
        let full = NSRange(location: 0, length: text.length)
        text.addAttributes([
            .foregroundColor: UIColor.red,
            .font: UIFont.systemFont(ofSize: 42),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ], range: full)
        text.addAttribute(
            VersoTextAttribute.inlineStyle,
            value: NSNumber(value: InlineStyle.bold.rawValue),
            range: full
        )

        let restored = TextPayload(semantic: text).attributedNS

        #expect(restored.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(restored.attribute(.font, at: 0, effectiveRange: nil) == nil)
        #expect(restored.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
        #expect(AttributedText.style(of: restored, in: full) == .bold)
    }

    @Test("Rendering applies the theme, and two themes give different ink")
    func renderingFollowsTheme() throws {
        let catalog = ThemeCatalog.shared
        let light = try #require(catalog.theme(id: "iron-gall"))
        let dark = try #require(catalog.theme(id: "midnight-oil"))
        let semantic = styled("word", [])

        let a = AttributedText.rendered(semantic, theme: light, bodySize: 17)
        let b = AttributedText.rendered(semantic, theme: dark, bodySize: 17)

        let inkA = a.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        let inkB = b.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(inkA != nil)
        #expect(inkA != inkB)
    }

    @Test("Bold and italic resolve to real font traits, not a synthetic slant")
    func fontTraitsAreApplied() {
        let plain = AttributedText.font(for: [], size: 17)
        let bold = AttributedText.font(for: .bold, size: 17)
        let both = AttributedText.font(for: [.bold, .italic], size: 17)

        #expect(!plain.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(both.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(both.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    @Test("Code runs are monospaced")
    func codeIsMonospaced() {
        let code = AttributedText.font(for: .code, size: 17)
        #expect(code.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    }

    // MARK: - Toggling

    @Test("Toggling a mark on and off returns the text to where it started")
    func togglingIsReversible() {
        let original = styled("hello world", [])
        let range = NSRange(location: 0, length: 5)

        let bolded = AttributedText.setting(.bold, enabled: true, in: range, of: original)
        #expect(AttributedText.style(of: bolded, in: range) == .bold)

        let unbolded = AttributedText.setting(.bold, enabled: false, in: range, of: bolded)
        #expect(AttributedText.style(of: unbolded, in: range) == [])
        #expect(unbolded.attribute(VersoTextAttribute.inlineStyle, at: 0, effectiveRange: nil) == nil)
    }

    @Test("Toggling one mark leaves the others alone")
    func togglingIsIndependent() {
        let range = NSRange(location: 0, length: 4)
        let both = AttributedText.setting(
            .italic,
            enabled: true,
            in: range,
            of: AttributedText.setting(.bold, enabled: true, in: range, of: styled("word", []))
        )
        #expect(AttributedText.style(of: both, in: range) == [.bold, .italic])

        let italicOnly = AttributedText.setting(.bold, enabled: false, in: range, of: both)
        #expect(AttributedText.style(of: italicOnly, in: range) == .italic)
    }

    /// A toolbar button that lights up for a selection where only half the text
    /// is bold is lying about what pressing it will do.
    @Test("A mixed selection reports no common mark")
    func mixedSelectionHasNoCommonStyle() {
        let text = NSMutableAttributedString(attributedString: styled("boldplain", []))
        text.addAttribute(
            VersoTextAttribute.inlineStyle,
            value: NSNumber(value: InlineStyle.bold.rawValue),
            range: NSRange(location: 0, length: 4)
        )

        #expect(AttributedText.style(of: text, in: NSRange(location: 0, length: 4)) == .bold)
        #expect(AttributedText.style(of: text, in: NSRange(location: 0, length: 9)) == [])
    }

    @Test("Toggling outside the text is ignored rather than trapping")
    func outOfBoundsToggleIsSafe() {
        let text = styled("short", [])
        let result = AttributedText.setting(.bold, enabled: true, in: NSRange(location: 3, length: 99), of: text)
        #expect(result.string == "short")
    }
}

@Suite("Wiki links")
struct WikiLinkTests {

    @Test("Completed links are found with their ranges")
    func matchesAreFound() {
        let text = "See [[Ledger]] and [[Iron Gall]] today."
        let matches = WikiLink.matches(in: text)

        #expect(matches.map(\.title) == ["Ledger", "Iron Gall"])
        #expect((text as NSString).substring(with: matches[0].range) == "[[Ledger]]")
    }

    @Test("Empty and malformed brackets are not links", arguments: [
        "[[]]", "[[   ]]", "[[unclosed", "closed]]", "[ [spaced] ]", "[[with\nnewline]]",
    ])
    func malformedIsIgnored(text: String) {
        #expect(WikiLink.matches(in: text).isEmpty)
    }

    @Test("An open bracket pair before the caret is a draft")
    func draftIsDetected() throws {
        let text = "link to [[Led"
        let draft = try #require(WikiLink.draft(in: text, caret: (text as NSString).length))

        #expect(draft.query == "Led")
        #expect((text as NSString).substring(with: draft.range) == "[[Led")
    }

    @Test("An empty draft is still a draft, so the suggester opens on `[[`")
    func emptyDraftIsDetected() throws {
        let draft = try #require(WikiLink.draft(in: "start [[", caret: 8))
        #expect(draft.query.isEmpty)
    }

    @Test("A caret after a finished link does not reopen it")
    func closedLinkIsNotADraft() {
        let text = "see [[Ledger]] now"
        #expect(WikiLink.draft(in: text, caret: (text as NSString).length) == nil)
    }

    @Test("A draft does not reach across a line break")
    func draftStopsAtNewline() {
        let text = "[[open\nnew line"
        #expect(WikiLink.draft(in: text, caret: (text as NSString).length) == nil)
    }

    @Test("There is no draft where there are no brackets")
    func noBracketsNoDraft() {
        #expect(WikiLink.draft(in: "just words", caret: 10) == nil)
        #expect(WikiLink.draft(in: "", caret: 0) == nil)
        #expect(WikiLink.draft(in: "a", caret: 1) == nil)
    }

    /// Ranges are handed straight to `UITextView`, which counts UTF-16.
    /// Counting `Character`s would put the replacement in the wrong place the
    /// moment a note contains an emoji.
    @Test("Draft ranges are UTF-16 offsets")
    func draftRangesAreUTF16() throws {
        let text = "🧪🧪 [[Led"
        let ns = text as NSString
        let draft = try #require(WikiLink.draft(in: text, caret: ns.length))

        #expect(draft.query == "Led")
        #expect(ns.substring(with: draft.range) == "[[Led")
        #expect(draft.range.location == 5)
    }

    @Test("Markup is what completion inserts")
    func markupIsWellFormed() {
        #expect(WikiLink.markup(for: "Ledger") == "[[Ledger]]")
        #expect(WikiLink.titles(in: WikiLink.markup(for: "Ledger")) == ["Ledger"])
    }
}

@Suite("Typewriter scroll")
struct TypewriterScrollerTests {

    private let scroller = TypewriterScroller()

    @Test("The caret is pulled to the anchor line")
    func scrollsToAnchor() throws {
        let target = try #require(scroller.targetOffset(
            caretMidY: 2000,
            currentOffset: 0,
            viewportHeight: 800,
            contentHeight: 5000
        ))
        #expect(abs(target - (2000 - 800 * 0.42)) < 0.001)
    }

    /// Without a deadband, every keystroke that nudges the caret produces a
    /// scroll, which reads as the page shivering.
    @Test("A caret already near the anchor does not move the page")
    func toleranceSuppressesJitter() {
        let anchored = 2000 - 800 * 0.42
        #expect(scroller.targetOffset(
            caretMidY: 2000,
            currentOffset: anchored + 10,
            viewportHeight: 800,
            contentHeight: 5000
        ) == nil)
    }

    @Test("Scrolling clamps at the top of the note")
    func clampsAtTop() throws {
        let target = try #require(scroller.targetOffset(
            caretMidY: 20,
            currentOffset: 400,
            viewportHeight: 800,
            contentHeight: 5000
        ))
        #expect(target == 0)
    }

    @Test("Scrolling clamps at the end of the note")
    func clampsAtBottom() throws {
        let target = try #require(scroller.targetOffset(
            caretMidY: 4900,
            currentOffset: 0,
            viewportHeight: 800,
            contentHeight: 5000
        ))
        #expect(target == 4200)
    }

    /// Once clamped, the caret cannot reach the anchor. Comparing against the
    /// ideal offset rather than the reachable one would ask for a scroll on
    /// every keystroke forever.
    @Test("A clamped caret settles instead of asking to scroll repeatedly")
    func clampedOffsetSettles() {
        #expect(scroller.targetOffset(
            caretMidY: 4900,
            currentOffset: 4200,
            viewportHeight: 800,
            contentHeight: 5000
        ) == nil)
    }

    @Test("The bottom inset lets the last line reach the anchor")
    func bottomInsetIsReserved() {
        #expect(abs(scroller.bottomInset(viewportHeight: 800) - 800 * 0.58) < 0.001)
    }

    @Test("Disabled, it never scrolls and reserves nothing")
    func disabledDoesNothing() {
        let off = TypewriterScroller(isEnabled: false)
        #expect(off.bottomInset(viewportHeight: 800) == 0)
        #expect(off.targetOffset(caretMidY: 2000, currentOffset: 0, viewportHeight: 800, contentHeight: 5000) == nil)
    }

    @Test("A zero-height viewport is survivable")
    func zeroViewportIsSafe() {
        #expect(scroller.targetOffset(caretMidY: 10, currentOffset: 0, viewportHeight: 0, contentHeight: 0) == nil)
        #expect(scroller.bottomInset(viewportHeight: 0) == 0)
    }
}

@Suite("Link graph")
struct LinkGraphTests {

    @Test("Adding edges fills both directions")
    func edgesAreBidirectional() {
        let a = UUID(), b = UUID(), c = UUID()
        var graph = LinkGraph()
        graph.replaceOutgoing(for: a, with: [b, c], unresolvedTitles: [])

        #expect(graph.links(from: a) == [b, c])
        #expect(graph.backlinks(to: b) == [a])
        #expect(graph.backlinks(to: c) == [a])
        #expect(graph.backlinks(to: a).isEmpty)
    }

    /// The reverse map is the part that silently rots: delete a link and the
    /// backlink stays unless the replacement repairs it.
    @Test("Removing a link removes its backlink")
    func replacingRepairsTheReverseMap() {
        let a = UUID(), b = UUID(), c = UUID()
        var graph = LinkGraph()
        graph.replaceOutgoing(for: a, with: [b, c], unresolvedTitles: [])
        graph.replaceOutgoing(for: a, with: [c], unresolvedTitles: [])

        #expect(graph.backlinks(to: b).isEmpty)
        #expect(graph.backlinks(to: c) == [a])
    }

    @Test("Two notes can link to the same target")
    func sharedTarget() {
        let a = UUID(), b = UUID(), target = UUID()
        var graph = LinkGraph()
        graph.replaceOutgoing(for: a, with: [target], unresolvedTitles: [])
        graph.replaceOutgoing(for: b, with: [target], unresolvedTitles: [])
        #expect(graph.backlinks(to: target) == [a, b])

        graph.replaceOutgoing(for: a, with: [], unresolvedTitles: [])
        #expect(graph.backlinks(to: target) == [b])
    }

    @Test("Deleting a note clears it from both directions")
    func removingANoteClearsBothDirections() {
        let a = UUID(), b = UUID()
        var graph = LinkGraph()
        graph.replaceOutgoing(for: a, with: [b], unresolvedTitles: [])
        graph.replaceOutgoing(for: b, with: [a], unresolvedTitles: [])

        graph.remove(note: a)

        #expect(graph.links(from: a).isEmpty)
        #expect(graph.backlinks(to: b).isEmpty)
        #expect(graph.backlinks(to: a).isEmpty)
    }

    @Test("Unresolved titles are kept, since they are an offer to create a note")
    func unresolvedTitlesAreKept() {
        let a = UUID()
        var graph = LinkGraph()
        graph.replaceOutgoing(for: a, with: [], unresolvedTitles: ["Somewhere"])
        #expect(graph.unresolved[a] == ["Somewhere"])
    }

    @Test("Title matching ignores case and surrounding space")
    func titleKeyNormalises() {
        #expect(LinkIndexBuilder.titleKey("  Iron Gall ") == "iron gall")
        #expect(LinkIndexBuilder.titleKey("IRON GALL") == LinkIndexBuilder.titleKey("iron gall"))
    }
}
