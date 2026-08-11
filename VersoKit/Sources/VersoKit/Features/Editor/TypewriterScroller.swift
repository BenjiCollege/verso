import CoreGraphics

/// Where the caret should sit, and how far to scroll to keep it there.
///
/// Pure arithmetic with no view types, so the behaviour that is easiest to get
/// subtly wrong — and impossible to eyeball — is the part that is tested.
struct TypewriterScroller: Equatable, Sendable {

    /// Fraction of the viewport height the caret is held at. Slightly above
    /// centre: text you have written should occupy more of the screen than
    /// text you have not.
    var anchorFraction: CGFloat = 0.42

    /// How far the caret may drift from the anchor before a scroll happens.
    /// Without this, every keystroke that changes the caret's y by a hair
    /// produces a scroll, which reads as the page shivering.
    var tolerance: CGFloat = 24

    var isEnabled: Bool = true

    /// Extra space below the content so the final line can still reach the
    /// anchor. Without it, typewriter mode quietly stops working near the end
    /// of a note — which is where most typing happens.
    func bottomInset(viewportHeight: CGFloat) -> CGFloat {
        guard isEnabled, viewportHeight > 0 else { return 0 }
        return max(0, viewportHeight * (1 - anchorFraction))
    }

    /// The scroll offset that puts the caret on the anchor line, or `nil` when
    /// the caret is already close enough to leave alone.
    ///
    /// - Parameters:
    ///   - caretMidY: caret centre in content coordinates.
    ///   - currentOffset: the scroll view's current vertical offset.
    ///   - viewportHeight: visible height.
    ///   - contentHeight: total scrollable height, including `bottomInset`.
    func targetOffset(
        caretMidY: CGFloat,
        currentOffset: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat? {
        guard isEnabled, viewportHeight > 0 else { return nil }

        let desired = caretMidY - viewportHeight * anchorFraction
        let maximum = max(0, contentHeight - viewportHeight)
        let clamped = min(max(desired, 0), maximum)

        // Once clamped at either end the caret cannot reach the anchor, so the
        // comparison has to be against the offset we can actually reach — not
        // against the ideal, which would leave us scrolling forever.
        guard abs(clamped - currentOffset) > tolerance else { return nil }
        return clamped
    }
}
