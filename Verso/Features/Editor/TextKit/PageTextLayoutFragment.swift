import UIKit

/// What a fragment needs to draw the page under its own lines.
///
/// A `Sendable` value rather than a reference to live theme state: fragments
/// are rebuilt when layout is invalidated, so a theme change invalidates and
/// the new fragments carry the new snapshot. Nothing is shared and mutated.
struct PageRenderingSnapshot: Sendable, Equatable {
    /// `nil` draws no rule — which is what `plain` stock does.
    var rule: HexColor?
    var lineWidth: CGFloat = Layout.hairline
    var opacity: Double = 1
    /// Manuscript paper's lighter mid-row guide.
    var showsBaselineGuides: Bool = false
    /// Width to stroke across. Taken from the text container rather than the
    /// fragment, so a short last line still gets a full-width rule.
    var containerWidth: CGFloat = 0

    static let none = PageRenderingSnapshot(rule: nil)

    var drawsAnything: Bool { rule != nil && containerWidth > 0 }
}

/// Draws ruled paper beneath the text it belongs to.
///
/// Rules are placed on the actual typographic bounds of each line fragment
/// rather than on an assumed uniform line height. That is the whole reason this
/// is a `NSTextLayoutFragment` subclass and not a background view: with mixed
/// inline sizes, an inline code run, or any Dynamic Type size, an assumed
/// spacing drifts away from the baselines within a paragraph or two.
final class PageTextLayoutFragment: NSTextLayoutFragment {

    /// Assigned by `PageLayoutDelegate` at creation.
    var snapshot: PageRenderingSnapshot = .none

    override func draw(at point: CGPoint, in context: CGContext) {
        drawRules(at: point, in: context)
        super.draw(at: point, in: context)
    }

    private func drawRules(at point: CGPoint, in context: CGContext) {
        guard snapshot.drawsAnything, let rule = snapshot.rule else { return }

        context.saveGState()
        defer { context.restoreGState() }

        context.setAlpha(snapshot.opacity)
        context.setLineWidth(snapshot.lineWidth)
        context.setStrokeColor(
            UIColor(red: rule.red, green: rule.green, blue: rule.blue, alpha: rule.alpha).cgColor
        )

        let leading = point.x
        let trailing = point.x + snapshot.containerWidth

        for line in textLineFragments {
            // Line fragment bounds are relative to the fragment's origin.
            // Half-pixel alignment keeps a hairline from smearing across two
            // device pixels.
            let baseline = point.y + line.typographicBounds.maxY
            let y = (baseline * 2).rounded() / 2

            context.move(to: CGPoint(x: leading, y: y))
            context.addLine(to: CGPoint(x: trailing, y: y))

            if snapshot.showsBaselineGuides {
                let guideY = y - line.typographicBounds.height / 2
                context.move(to: CGPoint(x: leading, y: guideY))
                context.addLine(to: CGPoint(x: trailing, y: guideY))
            }
        }

        context.strokePath()
    }
}

/// Vends the custom fragment.
///
/// `snapshot` is `nonisolated(unsafe)` because `NSTextLayoutManagerDelegate`
/// callbacks are not statically known to be main-actor-isolated on every SDK,
/// while in practice `UITextView` performs all of its layout on the main
/// thread. The property is written only from `RichTextCoordinator`, which is
/// `@MainActor`, and read only from the layout callback on the same thread.
final class PageLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {

    nonisolated(unsafe) var snapshot: PageRenderingSnapshot = .none

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = PageTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.snapshot = snapshot
        return fragment
    }
}
