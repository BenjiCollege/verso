import SwiftUI

/// The note, read rather than edited.
///
/// No chrome, no caret, nothing tappable except the way out. The reveal plays
/// once on entry; tapping anywhere skips to the end, because a reveal you have
/// to sit through is a reveal you come to resent.
struct ReadModeView: View {
    let note: Note

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var appTheme
    @Environment(\.stock) private var appStock
    @Environment(\.themeCatalog) private var catalog
    @Environment(\.motion) private var motion

    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = Typography.Role.body.pointSize

    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.readingPreferences) private var reading

    @State private var startedAt: Date?
    @State private var isComplete = false

    /// The way out, and the way to change how it reads. Visible on arrival —
    /// a reading view you cannot leave without guessing where to tap is a trap,
    /// and this one used to hide its only exit behind a system overlay.
    @State private var isShowingChrome = true
    @State private var isShowingControls = false
    @State private var dragOffset: CGFloat = 0

    /// Resolved once on entry. The timeline ticks sixty times a second, and
    /// sorting blocks or decoding payloads on each of those ticks is exactly
    /// the kind of per-frame work section 9 rules out.
    @State private var blocks: [Block] = []
    @State private var totalDuration: TimeInterval = 0
    /// Unarchiving an `NSAttributedString` sixty times a second would be worse
    /// than the reveal is good.
    @State private var texts: [UUID: NSAttributedString] = [:]

    private var theme: Theme { catalog.theme(id: note.themeID) ?? appTheme }
    private var stock: Stock { catalog.stock(id: note.stockID) ?? appStock }

    private var plan: RevealPlan {
        motion.revealPlan(for: RevealStyle(rawValue: note.revealStyleID ?? "") ?? .fadeUp)
    }

    var body: some View {
        ZStack {
            theme.stock.ignoresSafeArea()
            PageBackground().ignoresSafeArea()

            TimelineView(.animation(paused: isComplete)) { timeline in
                let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                page(elapsed: elapsed)
                    .onChange(of: elapsed >= totalDuration) { _, finished in
                        if finished { isComplete = true }
                    }
            }
        }
        .offset(y: dragOffset)
        .versoTheme(theme, stock: stock)
        .statusBarHidden(!isShowingChrome)
        .persistentSystemOverlays(isShowingChrome ? .automatic : .hidden)
        .contentShape(.rect)
        .onTapGesture { handleTap() }
        // Pull down to leave, the way every other full-screen reader works.
        // `fullScreenCover` offers no dismiss gesture of its own.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    guard value.translation.height > 0 else { return }
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(motion.animation(.settle)) { dragOffset = 0 }
                    }
                }
        )
        .overlay(alignment: .top) { chrome }
        .sheet(isPresented: $isShowingControls) {
            ReadingControlsSheet()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .task {
            blocks = note.orderedBlocks
            texts = Dictionary(
                uniqueKeysWithValues: blocks.compactMap { block in
                    guard block.type == .text,
                          let payload = try? block.decoded(as: TextPayload.self)
                    else { return nil }
                    return (block.id, payload.attributedNS)
                }
            )
            totalDuration = computeTotalDuration()
            startedAt = Date()
            if plan.style == .none { isComplete = true }
        }
        .accessibilityAction(named: Text("Skip the reveal")) { skip() }
    }

    // MARK: - Page

    private func page(elapsed: TimeInterval) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.Space.regular) {
                if !note.title.isEmpty {
                    Text(note.title)
                        .versoText(.display)
                        .foregroundStyle(theme.ink)
                        .revealed(plan: plan, index: 0, elapsed: elapsed)
                        .padding(.bottom, Layout.Space.snug)
                }

                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    blockView(for: block, index: index + 1, elapsed: elapsed)
                }
            }
            .padding(.horizontal, Layout.pageMargin * reading.marginScale)
            .padding(.vertical, Layout.Space.vast)
        }
        .scrollIndicators(.hidden)
        .pageMeasure()
    }

    /// Text blocks reveal within themselves; everything else reveals whole.
    /// A checklist has no glyphs to stagger, and pretending otherwise would
    /// mean re-implementing every block view read-only.
    @ViewBuilder
    private func blockView(for block: Block, index: Int, elapsed: TimeInterval) -> some View {
        if let semantic = texts[block.id] {
            RevealingText(
                semantic: semantic,
                theme: theme,
                bodySize: bodySize,
                plan: plan,
                elapsed: max(0, elapsed - plan.delay(forUnit: index))
            )
            .revealed(plan: plan, index: index, elapsed: elapsed)
        } else {
            BlockRenderer(block: block)
                .disabled(true)
                .allowsHitTesting(false)
                .revealed(plan: plan, index: index, elapsed: elapsed)
        }
    }

    /// A tap means the most useful thing available: skip a reveal still running,
    /// otherwise show or hide the chrome.
    private func handleTap() {
        if !isComplete {
            skip()
        } else {
            withAnimation(motion.animation(.settle)) { isShowingChrome.toggle() }
        }
    }

    @ViewBuilder
    private var chrome: some View {
        if isShowingChrome {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Done", systemImage: "chevron.down")
                        .versoText(.chromeLabel)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)

                Spacer(minLength: Layout.Space.regular)

                Button {
                    isShowingControls = true
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: Layout.Space.regular, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Reading settings"))
            }
            .padding(.horizontal, Layout.Space.regular)
            .padding(.vertical, Layout.Space.cosy)
            .background(.regularMaterial)
            .transition(motion.transition(.settle, motion: .opacity))
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: Layout.Space.regular, weight: .medium))
                .foregroundStyle(theme.inkSecondary)
                .frame(width: Layout.minimumHitTarget, height: Layout.minimumHitTarget)
                .background(theme.inset, in: .circle)
                .contentShape(.circle)
        }
        .padding(Layout.Space.regular)
        .accessibilityLabel(Text("Close Read Mode"))
    }

    // MARK: - Timing

    /// The longest text block sets the tail, since its own words continue
    /// arriving after its block has landed.
    private func computeTotalDuration() -> TimeInterval {
        let ordered = note.orderedBlocks
        let blockTail = plan.totalDuration(unitCount: ordered.count + 1)
        guard plan.granularity != .block else { return blockTail }

        let longest = ordered.compactMap { block -> Int? in
            guard block.type == .text, let payload = try? block.decoded(as: TextPayload.self) else { return nil }
            return RevealUnits.count(in: payload.plain, granularity: plan.granularity)
        }.max() ?? 0

        return blockTail + plan.totalDuration(unitCount: longest)
    }

    private func skip() {
        guard !isComplete else { return }
        motion.run(.settle) {
            startedAt = Date().addingTimeInterval(-totalDuration)
            isComplete = true
        }
    }
}
