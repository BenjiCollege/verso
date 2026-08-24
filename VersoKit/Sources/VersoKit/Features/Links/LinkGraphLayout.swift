import CoreGraphics
import Foundation

/// Where every note sits on the map.
///
/// Deliberately *not* a force-directed simulation. A spring layout settles
/// somewhere slightly different depending on the seed, the tick count and the
/// order the nodes happened to arrive in, which means the same library draws a
/// different picture on every launch and the note you learned the position of
/// has moved. A map you cannot learn is not a map.
///
/// So: concentric rings. The most connected note takes the middle, the rest are
/// filled outwards in a breadth-first walk of the graph, so a note's neighbours
/// land near it without anything having to be simulated. Every tie is broken by
/// degree, then title, then id — all of which are properties of the library
/// rather than of this run — so the same library always produces the same
/// arrangement.
///
/// A pure value with no SwiftData in it, so the arrangement can be tested
/// without a store and drawn without a fetch.
struct LinkGraphLayout: Equatable {

    struct Node: Identifiable, Equatable {
        let id: UUID
        /// Already resolved for display — the layout never sees an empty title.
        let title: String
        /// Position in a unit square, origin top-left. How big that square is
        /// is the view's business.
        let unitPosition: CGPoint
        let ring: Int
        /// How many distinct notes this one is joined to, either way round.
        /// Drives the size of the dot: the hubs should be findable.
        let neighbourCount: Int
        /// Titles this note links to, and titles that link to it. Carried on
        /// the node because a drawing is invisible to VoiceOver, and these are
        /// what a node has to be able to say about itself instead.
        let linkedTo: [String]
        let linkedFrom: [String]
    }

    struct Edge: Equatable {
        let source: UUID
        let target: UUID
        let start: CGPoint
        let end: CGPoint
        /// Both notes link to each other. One line, drawn once — two lines
        /// between the same pair of dots is just a thicker line.
        let isMutual: Bool
    }

    var nodes: [Node] = []
    var edges: [Edge] = []
    /// Rings occupied, including the single-node centre. Zero when empty.
    var ringCount: Int = 0
    /// Eligible notes that link to nothing and that nothing links to. Not
    /// drawn — a hundred unconnected dots is noise, not a graph — but worth
    /// saying out loud, because their absence is otherwise a mystery.
    var unlinkedCount: Int = 0
    /// Distinct `[[titles]]` that match no note. The offer to create one, and
    /// the reason a link you thought you made isn't on the map.
    var unresolvedCount: Int = 0

    static let empty = LinkGraphLayout()

    // MARK: - Building

    /// Arranges the notes named in `titles`, and only those.
    ///
    /// `titles` is the whitelist as well as the display names: an edge whose
    /// other end is missing from it is dropped whole, rather than drawn as an
    /// unnamed dot. That is how the vault rule is enforced here — the caller
    /// filters with `VaultPolicy`, and a locked or hidden note cannot leak in
    /// as somebody else's neighbour.
    static func make(graph: LinkGraph, titles: [UUID: String]) -> LinkGraphLayout {
        var outgoing: [UUID: Set<UUID>] = [:]
        var neighbours: [UUID: Set<UUID>] = [:]

        for (source, targets) in graph.outgoing where titles[source] != nil {
            let visible = targets.filter { titles[$0] != nil && $0 != source }
            guard !visible.isEmpty else { continue }
            outgoing[source] = visible
            for target in visible {
                neighbours[source, default: []].insert(target)
                neighbours[target, default: []].insert(source)
            }
        }

        var incoming: [UUID: Set<UUID>] = [:]
        for (source, targets) in outgoing {
            for target in targets { incoming[target, default: []].insert(source) }
        }

        let unresolved = Set(graph.unresolved.filter { titles[$0.key] != nil }.values.joined())
        let order = walkOrder(neighbours: neighbours, titles: titles)
        let rings = rings(over: order)

        var layout = LinkGraphLayout(
            ringCount: rings.count,
            unlinkedCount: titles.count - neighbours.count,
            unresolvedCount: unresolved.count
        )

        var positions: [UUID: CGPoint] = [:]
        for (ring, ids) in rings.enumerated() {
            for (slot, id) in ids.enumerated() {
                let position = position(ring: ring, slot: slot, inRingOf: ids.count, ringCount: rings.count)
                positions[id] = position
                layout.nodes.append(
                    Node(
                        id: id,
                        title: titles[id] ?? "",
                        unitPosition: position,
                        ring: ring,
                        neighbourCount: neighbours[id]?.count ?? 0,
                        linkedTo: names(of: outgoing[id], titles: titles),
                        linkedFrom: names(of: incoming[id], titles: titles)
                    )
                )
            }
        }

        for (source, targets) in outgoing {
            for target in targets.sorted(by: { $0.uuidString < $1.uuidString }) {
                let isMutual = outgoing[target]?.contains(source) == true
                // A mutual pair is discovered twice, once from each end. Keep
                // the pass with the lower id so it is drawn exactly once.
                if isMutual && source.uuidString > target.uuidString { continue }
                guard let start = positions[source], let end = positions[target] else { continue }
                layout.edges.append(
                    Edge(source: source, target: target, start: start, end: end, isMutual: isMutual)
                )
            }
        }
        // The dictionary walk above is in whatever order hashing gives, and the
        // draw order decides which line lies on top. Sorted, so two runs paint
        // the same picture.
        layout.edges.sort { ($0.source.uuidString, $0.target.uuidString) < ($1.source.uuidString, $1.target.uuidString) }

        return layout
    }

    // MARK: - Hit testing

    /// The node nearest a point in the unit square, if one is close enough.
    ///
    /// Lives here rather than in the view because a tap on a drawing has to be
    /// resolved by arithmetic either way, and arithmetic in a view is
    /// arithmetic nothing can test.
    func node(nearestTo unitPoint: CGPoint, within unitRadius: CGFloat) -> Node? {
        var best: Node?
        var bestDistance = unitRadius
        for node in nodes {
            let dx = node.unitPosition.x - unitPoint.x
            let dy = node.unitPosition.y - unitPoint.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance <= bestDistance else { continue }
            best = node
            bestDistance = distance
        }
        return best
    }

    // MARK: - Private

    private static func names(of ids: Set<UUID>?, titles: [UUID: String]) -> [String] {
        (ids ?? []).compactMap { titles[$0] }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Breadth-first from the best-connected note, then from the best-connected
    /// note of each remaining component. Neighbours are visited in the same
    /// order they are ranked, so a component comes out as a contiguous run and
    /// lands in adjacent slots.
    private static func walkOrder(neighbours: [UUID: Set<UUID>], titles: [UUID: String]) -> [UUID] {
        // Degree first so the hubs sit near the middle, then title, then id.
        // Titles are compared lowercased for the same reason the link index
        // matches them that way, and the id is the last resort that guarantees
        // there is never a tie left to break arbitrarily.
        func rank(_ id: UUID) -> (Int, String, String) {
            (-(neighbours[id]?.count ?? 0), (titles[id] ?? "").lowercased(), id.uuidString)
        }

        let seeds = neighbours.keys.sorted { rank($0) < rank($1) }
        var order: [UUID] = []
        var seen: Set<UUID> = []

        for seed in seeds where !seen.contains(seed) {
            var queue = [seed]
            seen.insert(seed)
            var head = 0
            while head < queue.count {
                let id = queue[head]
                head += 1
                order.append(id)
                for next in (neighbours[id] ?? []).sorted(by: { rank($0) < rank($1) }) where !seen.contains(next) {
                    seen.insert(next)
                    queue.append(next)
                }
            }
        }
        return order
    }

    /// Ring *k* holds `6k` notes. The circumference grows with the radius at
    /// the same rate, so the gap between two neighbours on a ring stays about
    /// constant however far out the map goes — which is what stops the outer
    /// rings turning into a solid band of labels.
    private static func rings(over order: [UUID]) -> [[UUID]] {
        var rings: [[UUID]] = []
        var index = 0
        var ring = 0
        while index < order.count {
            let capacity = ring == 0 ? 1 : 6 * ring
            let end = min(index + capacity, order.count)
            rings.append(Array(order[index..<end]))
            index = end
            ring += 1
        }
        return rings
    }

    private static func position(ring: Int, slot: Int, inRingOf count: Int, ringCount: Int) -> CGPoint {
        let centre = CGPoint(x: 0.5, y: 0.5)
        guard ring > 0, ringCount > 1 else { return centre }

        let radius = 0.5 * CGFloat(ring) / CGFloat(ringCount - 1)
        // Odd rings are turned half a slot. Without it every ring starts at the
        // same angle and the map reads as spokes on a wheel rather than as a
        // graph. Starting at -90° puts the first of each ring at the top, which
        // is where the eye starts looking for it.
        let turn = (CGFloat(slot) + (ring.isMultiple(of: 2) ? 0 : 0.5)) / CGFloat(max(count, 1))
        let angle = turn * 2 * .pi - .pi / 2
        return CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
    }
}
