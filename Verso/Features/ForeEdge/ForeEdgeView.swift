import SwiftUI

/// The fore-edge.
///
/// A vertical strip on the leading edge of an open note. Its height and density
/// encode how long the note is, its pattern encodes the theme, a clasp appears
/// when the note is locked, and dragging it scrubs backwards through history.
///
/// Everything around it is quiet on purpose.
struct ForeEdgeView: View {
    let model: ForeEdgeModel
    let versionCount: Int
    /// The version currently being previewed, or `nil` for the present.
    ///
    /// Letting go leaves this set: the drag *previews*, and restoring is a
    /// separate decision made in `VersionScrubBar`. Overwriting a note because
    /// a thumb happened to stop somewhere would be indefensible.
    @Binding var scrubIndex: Int?

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion
    @Environment(HapticEngine.self) private var haptics

    @State private var isScrubbing = false
    @State private var lastSample: (y: CGFloat, time: TimeInterval)?

    private let scrubber = ForeEdgeScrubber()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(theme.edge)

                leaves(in: proxy.size)

                if model.isLocked {
                    clasp
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }

                if isScrubbing, let scrubIndex {
                    thumb(at: scrubber.y(forVersionIndex: scrubIndex, height: proxy.size.height, versionCount: versionCount))
                }
            }
            .contentShape(.rect)
            .gesture(dragGesture(height: proxy.size.height))
        }
        .frame(width: Layout.foreEdgeWidth)
        .clipShape(.rect(cornerRadius: Layout.Radius.tight / 2))
        .accessibilityElement()
        .accessibilityLabel(Text("Version history"))
        .accessibilityValue(Text(accessibilityValue))
        // VoiceOver cannot drag a strip fourteen points wide, so the same
        // history is reachable by swiping up and down on it.
        .accessibilityAdjustableAction { direction in
            adjust(direction)
        }
        .accessibilityHint(Text("Swipe up and down to move through earlier versions"))
    }

    // MARK: - Drawing

    private func leaves(in size: CGSize) -> some View {
        Canvas { context, size in
            let inset = size.width * 0.15
            let usable = size.width - inset

            for leaf in model.leaves {
                let y = leaf.position * (size.height - 2) + 1
                let width = usable * leaf.extent
                let rect = CGRect(x: inset, y: y, width: width, height: 1)

                context.fill(
                    Path(rect),
                    with: .color(theme.gilt.opacity(0.25 + leaf.emphasis * 0.6))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var clasp: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: Layout.foreEdgeWidth * 0.55))
            .foregroundStyle(theme.gilt)
            .padding(Layout.Space.hair)
            .background(theme.edge, in: .circle)
            .accessibilityHidden(true)
    }

    private func thumb(at y: CGFloat) -> some View {
        Capsule()
            .fill(theme.gilt)
            .frame(width: Layout.foreEdgeWidth * 0.8, height: Layout.Space.snug)
            .position(x: Layout.foreEdgeWidth / 2, y: y)
            .shadow(color: theme.edge.opacity(0.6), radius: 2)
            .allowsHitTesting(false)
    }

    // MARK: - Scrubbing

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard versionCount > 0 else { return }

                if !isScrubbing {
                    guard scrubber.shouldActivate(translation: value.translation) else { return }
                    isScrubbing = true
                    haptics.beginScrub()
                }

                let sample = (y: value.location.y, time: value.time.timeIntervalSinceReferenceDate)
                haptics.updateScrub(velocity: scrubber.velocity(from: lastSample, to: sample))
                lastSample = sample

                let index = scrubber.versionIndex(
                    atY: value.location.y,
                    height: height,
                    versionCount: versionCount
                )
                // No animation while the thumb is down: the content should
                // track the finger, not chase it.
                if index != scrubIndex { scrubIndex = index }
            }
            .onEnded { _ in
                haptics.endScrub()
                lastSample = nil
                isScrubbing = false
            }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard versionCount > 0 else { return }
        let current = scrubIndex ?? -1
        let next = direction == .increment ? current + 1 : current - 1

        motion.run(.settle) {
            scrubIndex = next < 0 ? nil : min(next, versionCount - 1)
        }
        haptics.play(.checklistCheck)
    }

    private var accessibilityValue: String {
        guard let scrubIndex else { return String(localized: "Now") }
        return String(localized: "\(scrubIndex + 1) version\(scrubIndex == 0 ? "" : "s") back")
    }
}
