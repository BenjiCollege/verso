import SwiftData
import SwiftUI

/// The map of the library: which notes link to which.
///
/// One `Canvas` draws the whole thing — every line, every dot, every label.
/// A view per node and a view per edge would be several hundred of each in a
/// library of any size, and SwiftUI would be laying out a graph on every frame
/// of a pan. The cost of drawing it instead is that the result is opaque: it
/// cannot be tapped and VoiceOver cannot see it. Both are paid for below —
/// taps by hit-testing against the layout, VoiceOver by
/// `accessibilityChildren`, which supplies elements for a view that cannot
/// produce its own.
///
/// The graph itself comes from `LinkIndex`; the arrangement from
/// `LinkGraphLayout`, which is deterministic on purpose. This view decides
/// only how large the square is and what colour the ink is.
struct LinkGraphView: View {

    /// What a tapped node should do.
    ///
    /// The graph deliberately pushes nothing itself. `NavigationLink(value:)`
    /// needs a `navigationDestination` for `Note`, and which stack owns that
    /// destination depends on whether this is pushed from the library or shown
    /// in a sheet — the caller is the only one who knows.
    var onOpen: (Note) -> Void

    @Environment(LinkIndex.self) private var index
    @Environment(\.theme) private var theme

    /// The predicate narrows in the store; `VaultPolicy` is still the
    /// authority. Both, because the query is an optimisation and the policy is
    /// the rule — and the rule is one place so it cannot drift between the four
    /// screens that apply it.
    @Query(
        filter: #Predicate<Note> { !$0.isTrashed && !$0.isHidden },
        sort: [SortDescriptor(\Note.title)]
    )
    private var notes: [Note]

    @ScaledMetric(relativeTo: .footnote)
    private var labelSize: CGFloat = Typography.Role.chromeCaption.pointSize

    /// The distance between two rings. Scaled, because the labels under the
    /// dots are scaled: at AX5 the same spacing would have every title sitting
    /// on the one below it.
    @ScaledMetric(relativeTo: .footnote)
    private var ringGap: CGFloat = Layout.Space.vast * 2

    @ScaledMetric(relativeTo: .footnote)
    private var dotRadius: CGFloat = Layout.Space.snug

    var body: some View {
        // Built once per pass and handed down. As a computed property it would
        // be rebuilt by the canvas closure and again by the accessibility
        // children, which is three walks of the library for one render.
        let layout = LinkGraphLayout.make(graph: index.graph, titles: displayTitles)

        return Group {
            if layout.nodes.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    legend(layout)
                    map(layout)
                }
            }
        }
        .background(theme.canvas.ignoresSafeArea())
        .navigationTitle("Links")
        .task { await index.buildIfNeeded() }
    }

    // MARK: - Chrome

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No links yet", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("Write [[the title of another note]] and the two appear here, joined.")
        }
    }

    /// What the picture cannot say: how much of the library is on it.
    ///
    /// `FlowLayout` rather than an `HStack` — at AX5 these three pills are
    /// wider than any phone, and wrapping is the only honest answer.
    private func legend(_ layout: LinkGraphLayout) -> some View {
        FlowLayout(spacing: Layout.Space.snug) {
            VersoPill(
                title: String(localized: "\(layout.nodes.count) linked"),
                systemImage: "circle.hexagongrid"
            )
            VersoPill(
                title: String(localized: "\(layout.edges.count) connections"),
                systemImage: "arrow.left.arrow.right"
            )
            if layout.unlinkedCount > 0 {
                VersoPill(
                    title: String(localized: "\(layout.unlinkedCount) unlinked"),
                    systemImage: "circle.dotted"
                )
            }
            if layout.unresolvedCount > 0 {
                VersoPill(
                    title: String(localized: "\(layout.unresolvedCount) unresolved"),
                    systemImage: "questionmark.circle"
                )
            }
        }
        .padding(.horizontal, Layout.Space.regular)
        .padding(.vertical, Layout.Space.cosy)
    }

    // MARK: - The map

    private func map(_ layout: LinkGraphLayout) -> some View {
        GeometryReader { proxy in
            let square = side(for: layout, fitting: proxy.size)
            ScrollView([.horizontal, .vertical]) {
                plot(layout, side: square)
            }
            // A big library draws a square larger than the screen, and the
            // middle of it is where the hubs are. Opening on a corner would
            // show the sparsest part of the map first.
            .defaultScrollAnchor(.center)
        }
    }

    private func plot(_ layout: LinkGraphLayout, side: CGFloat) -> some View {
        let rect = plotRect(side: side)

        return Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            draw(layout, in: &context, rect: rect)
        }
        .frame(width: side, height: side)
        .contentShape(.rect)
        .onTapGesture { location in
            guard let node = layout.node(
                nearestTo: unitPoint(location, in: rect),
                within: tapTolerance / max(rect.width, 1)
            ) else { return }
            open(node)
        }
        .accessibilityLabel(Text("Link graph"))
        // A drawing has no children, so VoiceOver is given some: one element
        // per node, at the node's own position, saying what it is joined to and
        // opening it when activated. Without this the whole map is a single
        // unlabelled image.
        .accessibilityChildren { nodeElements(layout, rect: rect) }
    }

    private func draw(_ layout: LinkGraphLayout, in context: inout GraphicsContext, rect: CGRect) {
        for edge in layout.edges {
            let start = point(edge.start, in: rect)
            let end = point(edge.end, in: rect)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            if edge.isMutual {
                context.stroke(path, with: .color(theme.accent.opacity(0.45)), lineWidth: Layout.hairline * 3)
            } else {
                // Direction as a fade rather than an arrowhead: an arrow small
                // enough to fit between two dots this close together is a
                // smudge, and hundreds of them are hundreds of smudges. The
                // line simply starts at the note doing the linking and runs
                // out before it arrives.
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [theme.inkSecondary.opacity(0.5), theme.inkSecondary.opacity(0.06)]),
                        startPoint: start,
                        endPoint: end
                    ),
                    lineWidth: Layout.hairline * 2
                )
            }
        }

        for node in layout.nodes {
            let centre = point(node.unitPosition, in: rect)
            let radius = radius(for: node)
            let circle = Path(
                ellipseIn: CGRect(
                    x: centre.x - radius,
                    y: centre.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            // Filled with the paper first, so the lines that reach the dot stop
            // at its edge instead of crossing it.
            context.fill(circle, with: .color(theme.card))
            context.stroke(circle, with: .color(theme.accent), lineWidth: Layout.hairline * 4)

            context.draw(
                context.resolve(
                    Typography
                        .drawn(shortened(node.title), role: .chromeCaption, scaledSize: labelSize)
                        .foregroundStyle(theme.inkSecondary)
                ),
                at: CGPoint(x: centre.x, y: centre.y + radius + Layout.Space.tight),
                anchor: .top
            )
        }
    }

    private func nodeElements(_ layout: LinkGraphLayout, rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.nodes) { node in
                Button { open(node) } label: { Color.clear }
                    .frame(width: Layout.minimumHitTarget, height: Layout.minimumHitTarget)
                    .position(point(node.unitPosition, in: rect))
                    .accessibilityLabel(Text(node.title))
                    .accessibilityValue(Text(connections(of: node)))
                    .accessibilityHint(Text("Opens the note"))
            }
        }
    }

    // MARK: - Geometry

    /// Room round the rings for the labels, which hang below the outermost
    /// dots and are centred on them.
    private var margin: CGFloat { ringGap }

    private var tapTolerance: CGFloat { max(Layout.minimumHitTarget / 2, dotRadius * 2) }

    private func side(for layout: LinkGraphLayout, fitting viewport: CGSize) -> CGFloat {
        let rings = CGFloat(max(layout.ringCount - 1, 0))
        let fitted = min(viewport.width, viewport.height)
        return max(rings * 2 * ringGap + margin * 2, fitted, Layout.minimumHitTarget)
    }

    private func plotRect(side: CGFloat) -> CGRect {
        let usable = max(side - margin * 2, 1)
        return CGRect(x: margin, y: margin, width: usable, height: usable)
    }

    private func point(_ unit: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + unit.x * rect.width, y: rect.minY + unit.y * rect.height)
    }

    private func unitPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: (point.x - rect.minX) / max(rect.width, 1), y: (point.y - rect.minY) / max(rect.height, 1))
    }

    /// A hub is drawn larger, capped so that one note linked from forty others
    /// is a big dot rather than a planet.
    private func radius(for node: LinkGraphLayout.Node) -> CGFloat {
        let weight = min(CGFloat(node.neighbourCount), 8) / 8
        return dotRadius * (0.7 + weight * 0.6)
    }

    // MARK: - Content

    /// Only the notes the vault allows out, named the way a list names them.
    private var displayTitles: [UUID: String] {
        var titles: [UUID: String] = [:]
        for note in notes where VaultPolicy.isEligibleForIndexing(note) {
            titles[note.id] = note.title.isEmpty ? String(localized: "Untitled") : note.title
        }
        return titles
    }

    private var notesByID: [UUID: Note] {
        Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func open(_ node: LinkGraphLayout.Node) {
        guard let note = notesByID[node.id] else { return }
        onOpen(note)
    }

    /// A label is only as long as it can be without landing on its neighbour.
    ///
    /// Truncated by character count rather than by measuring: measuring means
    /// laying out text once per node per frame, and the ring spacing already
    /// fixes how much room there is. A crude cap that is stable beats an exact
    /// one that costs a text layout to find.
    private func shortened(_ title: String) -> String {
        let limit = 16
        guard title.count > limit else { return title }
        return title.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// What a node says about itself, since the drawing says nothing.
    private func connections(of node: LinkGraphLayout.Node) -> String {
        var parts: [String] = []
        if !node.linkedTo.isEmpty {
            parts.append(String(localized: "Links to \(named(node.linkedTo))"))
        }
        if !node.linkedFrom.isEmpty {
            parts.append(String(localized: "Linked from \(named(node.linkedFrom))"))
        }
        return parts.joined(separator: ". ")
    }

    /// Names, up to a point. A hub with sixty backlinks read out in full is a
    /// minute of speech before the next element.
    private func named(_ titles: [String]) -> String {
        let limit = 5
        let shown = Array(titles.prefix(limit))
        let phrase = shown.formatted(.list(type: .and))
        guard titles.count > shown.count else { return phrase }
        return String(localized: "\(phrase) and \(titles.count - shown.count) more")
    }
}
