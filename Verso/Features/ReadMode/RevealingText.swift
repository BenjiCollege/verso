import SwiftUI
import UIKit

/// Read-only text that arrives one word or glyph at a time.
///
/// The reveal is applied as *rendering attributes* on the TextKit 2 layout
/// manager. That is the whole reason section 7 requires TextKit 2 here: the
/// text storage is never touched, so nothing re-lays-out, and a paragraph
/// arriving word by word costs no more than a paragraph sitting still.
struct RevealingText: UIViewRepresentable {

    let semantic: NSAttributedString
    let theme: Theme
    let bodySize: CGFloat
    let plan: RevealPlan
    /// Seconds since the reveal began. Driven by a `TimelineView`.
    let elapsed: TimeInterval

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> VersoTextView {
        let textView = VersoTextView.make()
        textView.isEditable = false
        textView.isSelectable = true
        context.coordinator.apply(self, to: textView, forcingLayout: true)
        return textView
    }

    func updateUIView(_ textView: VersoTextView, context: Context) {
        context.coordinator.apply(self, to: textView, forcingLayout: false)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: VersoTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }

    @MainActor
    final class Coordinator {
        private var lastText: NSAttributedString?
        private var lastThemeID: String?
        private var ranges: [NSRange] = []
        /// Units below this are fully arrived and need no further work.
        private var settledPrefix = 0

        func apply(_ parent: RevealingText, to textView: VersoTextView, forcingLayout: Bool) {
            let needsRestyle = forcingLayout
                || lastThemeID != parent.theme.id
                || lastText?.isEqual(to: parent.semantic) != true

            if needsRestyle {
                textView.attributedText = AttributedText.rendered(
                    parent.semantic,
                    theme: parent.theme,
                    bodySize: parent.bodySize
                )
                lastText = parent.semantic
                lastThemeID = parent.theme.id
                ranges = RevealUnits.ranges(in: parent.semantic.string, granularity: parent.plan.granularity)
                settledPrefix = 0
            }

            update(parent, in: textView)
        }

        private func update(_ parent: RevealingText, in textView: VersoTextView) {
            guard let layoutManager = textView.textLayoutManager, !ranges.isEmpty else { return }

            // A block-granularity plan, or a finished one, has nothing to hide.
            guard parent.plan.style != .none,
                  !parent.plan.isFinished(unitCount: ranges.count, elapsed: parent.elapsed)
            else {
                if settledPrefix < ranges.count {
                    layoutManager.invalidateRenderingAttributes(for: layoutManager.documentRange)
                    settledPrefix = ranges.count
                }
                return
            }

            let ink = UIColor(parent.theme.ink)

            // Everything not yet started is hidden as one range rather than one
            // per unit — a thousand-glyph paragraph would otherwise mean a
            // thousand attribute writes a frame.
            var firstUnstarted = ranges.count
            for index in settledPrefix..<ranges.count
            where parent.plan.progress(forUnit: index, elapsed: parent.elapsed) <= 0 {
                firstUnstarted = index
                break
            }

            if firstUnstarted < ranges.count {
                let start = ranges[firstUnstarted].location
                let hidden = NSRange(location: start, length: textView.attributedText.length - start)
                if hidden.length > 0, let textRange = layoutManager.textRange(for: hidden) {
                    layoutManager.setRenderingAttributes(
                        [.foregroundColor: ink.withAlphaComponent(0)],
                        for: textRange
                    )
                }
            }

            // Only the units actually in flight get individual treatment.
            var newSettled = settledPrefix
            for index in settledPrefix..<firstUnstarted {
                let progress = parent.plan.progress(forUnit: index, elapsed: parent.elapsed)
                let appearance = RevealAppearance.at(progress: progress, style: parent.plan.style)

                if progress >= 1 {
                    if index == newSettled { newSettled += 1 }
                    if let textRange = layoutManager.textRange(for: ranges[index]) {
                        layoutManager.setRenderingAttributes([.foregroundColor: ink], for: textRange)
                    }
                } else if let textRange = layoutManager.textRange(for: ranges[index]) {
                    layoutManager.setRenderingAttributes(
                        [.foregroundColor: ink.withAlphaComponent(appearance.opacity)],
                        for: textRange
                    )
                }
            }
            settledPrefix = newSettled
        }
    }
}

/// Applies a block-level reveal to any view.
///
/// Every style animates whole blocks in sequence; `typewriter`, `fadeUp` and
/// `blurIn` additionally reveal *within* text blocks, which `RevealingText`
/// handles. A checklist or a chart has no glyphs to stagger, so the block-level
/// pass is what makes those styles apply to a whole note rather than only to
/// its prose.
struct RevealedBlock: ViewModifier {
    let plan: RevealPlan
    let index: Int
    let elapsed: TimeInterval

    private var appearance: RevealAppearance {
        // Text blocks carry their own per-word reveal, so applying the block
        // opacity on top would double-fade them.
        guard plan.granularity == .block else { return .visible }
        return RevealAppearance.at(
            progress: plan.progress(forUnit: index, elapsed: elapsed),
            style: plan.style
        )
    }

    func body(content: Content) -> some View {
        let appearance = appearance
        return content
            .opacity(appearance.opacity)
            .offset(y: appearance.offsetY)
            .blur(radius: appearance.blurRadius)
            .scaleEffect(y: appearance.scaleY, anchor: .top)
    }
}

extension View {
    func revealed(plan: RevealPlan, index: Int, elapsed: TimeInterval) -> some View {
        modifier(RevealedBlock(plan: plan, index: index, elapsed: elapsed))
    }
}
