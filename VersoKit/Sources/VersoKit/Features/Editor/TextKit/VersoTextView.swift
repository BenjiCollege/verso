import UIKit

/// The TextKit 2 text view.
///
/// Non-scrolling: each text block is one of these, sized to its content, inside
/// the note's single scroll view. That is what lets typewriter scroll be a
/// property of the *note* rather than of one paragraph, and it is why the
/// caret's rect has to be reported outward in the note's coordinate space.
final class VersoTextView: UITextView {

    /// Suppresses the caret during transitions. A blinking caret that stays put
    /// while the page moves under it is the single most obvious tell that a
    /// transition is faked.
    var isCaretSuppressed = false

    /// A factory rather than an initialiser: declaring one here would stop the
    /// `init(usingTextLayoutManager:)` that selects TextKit 2 from being
    /// inherited, and TextKit 1 would silently take over.
    static func make() -> VersoTextView {
        let textView = VersoTextView(usingTextLayoutManager: true)
        textView.configure()
        return textView
    }

    private func configure() {
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        // The page draws its own texture; an opaque text view would cover it.
        isOpaque = false
        adjustsFontForContentSizeCategory = false
        autocorrectionType = .yes
        smartDashesType = .yes
        smartQuotesType = .yes
        // Links are followed by our own tap handling so that a `[[wiki link]]`
        // and an external URL can behave differently.
        dataDetectorTypes = []
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        isCaretSuppressed ? .zero : super.caretRect(for: position)
    }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        isCaretSuppressed ? [] : super.selectionRects(for: range)
    }

    /// The caret's rect in this view's coordinates, or `nil` when there is no
    /// selection to anchor to.
    var currentCaretRect: CGRect? {
        guard let range = selectedTextRange else { return nil }
        let rect = super.caretRect(for: range.end)
        return rect.isNull || rect.isInfinite ? nil : rect
    }
}

// MARK: - Range conversion

extension NSTextLayoutManager {
    /// Bridges the `NSRange` world that `UITextView` selections live in to the
    /// `NSTextRange` world TextKit 2 works in.
    func textRange(for range: NSRange) -> NSTextRange? {
        guard let contentManager = textContentManager else { return nil }
        let documentStart = contentManager.documentRange.location
        guard let start = contentManager.location(documentStart, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }
}
