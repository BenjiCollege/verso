import CoreGraphics
import Foundation
import Testing
@testable import VersoKit

@Suite("Link graph layout")
struct LinkGraphLayoutTests {

    /// Fixed ids, so a failure is reproducible and the tie-breaking rules are
    /// actually exercised rather than whatever `UUID()` happened to hand out.
    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
    }

    private func titles(_ pairs: [(Int, String)]) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: pairs.map { (Self.id($0.0), $0.1) })
    }

    /// Builds a graph the way the index does, keeping the order the edges were
    /// given in — which is what the determinism test varies.
    private func graph(_ edges: [(Int, Int)], unresolved: [Int: Set<String>] = [:]) -> LinkGraph {
        var order: [Int] = []
        var outgoing: [Int: Set<UUID>] = [:]

        for (source, target) in edges {
            if outgoing[source] == nil { order.append(source) }
            outgoing[source, default: []].insert(Self.id(target))
        }
        for source in unresolved.keys.sorted() where outgoing[source] == nil {
            order.append(source)
        }

        var graph = LinkGraph()
        for source in order {
            graph.replaceOutgoing(
                for: Self.id(source),
                with: outgoing[source] ?? [],
                unresolvedTitles: unresolved[source] ?? []
            )
        }
        return graph
    }

    @Test("The same library lays out identically however the graph was assembled")
    func layoutIsDeterministic() {
        let names = titles([(1, "Ledger"), (2, "Journal"), (3, "Index"), (4, "Marginalia"), (5, "Errata")])

        let first = LinkGraphLayout.make(
            graph: graph([(1, 2), (2, 3), (3, 1), (4, 1), (5, 4)]),
            titles: names
        )
        // The same edges, assembled in the opposite order — which is what
        // shuffles the dictionary and set iteration underneath. A layout that
        // reads any of that moves a note between two launches of the same app.
        let second = LinkGraphLayout.make(
            graph: graph([(5, 4), (4, 1), (3, 1), (2, 3), (1, 2)]),
            titles: names
        )

        #expect(first == second)
        #expect(first.nodes.count == 5)
    }

    @Test("The best-connected note takes the centre")
    func hubIsCentred() throws {
        let names = titles([(1, "Hub"), (2, "A"), (3, "B"), (4, "C")])
        let layout = LinkGraphLayout.make(graph: graph([(2, 1), (3, 1), (4, 1)]), titles: names)

        let centre = try #require(layout.nodes.first { $0.ring == 0 })
        #expect(centre.id == Self.id(1))
        #expect(centre.unitPosition == CGPoint(x: 0.5, y: 0.5))
    }

    @Test("Every node lands inside the unit square")
    func nodesStayInsideTheSquare() {
        let names = titles((1...40).map { ($0, "Note \($0)") })
        let layout = LinkGraphLayout.make(graph: graph((2...40).map { ($0, 1) }), titles: names)

        #expect(layout.nodes.count == 40)
        for node in layout.nodes {
            #expect((0...1).contains(node.unitPosition.x))
            #expect((0...1).contains(node.unitPosition.y))
        }
    }

    /// The vault rule, and the reason the layout is given a title map rather
    /// than reading the store itself: a note that is not in it is not on the
    /// map, and neither is the line that would have pointed at it.
    @Test("A locked note is not drawn, and the links touching it are dropped whole")
    func ineligibleNotesAndTheirEdgesVanish() throws {
        // Note 3 is locked, so the caller left it out of the title map. It
        // links to 2 and 1 links to it.
        let visible = titles([(1, "Open"), (2, "Also Open")])
        let layout = LinkGraphLayout.make(graph: graph([(1, 3), (2, 1), (3, 2)]), titles: visible)

        #expect(Set(layout.nodes.map(\.id)) == [Self.id(1), Self.id(2)])
        #expect(layout.edges.count == 1)

        let edge = try #require(layout.edges.first)
        #expect(edge.source == Self.id(2))
        #expect(edge.target == Self.id(1))

        // And the surviving nodes know nothing about it: note 1's only outgoing
        // link went to the locked note, so it has none.
        let open = try #require(layout.nodes.first { $0.id == Self.id(1) })
        #expect(open.linkedTo.isEmpty)
        #expect(open.linkedFrom == ["Also Open"])
    }

    @Test("Two notes that link to each other share one line")
    func mutualLinksAreDrawnOnce() {
        let names = titles([(1, "Recto"), (2, "Verso")])
        let layout = LinkGraphLayout.make(graph: graph([(1, 2), (2, 1)]), titles: names)

        #expect(layout.edges.count == 1)
        #expect(layout.edges.first?.isMutual == true)
    }

    @Test("A note nothing links to is counted rather than drawn")
    func unlinkedNotesAreCountedOnly() {
        let names = titles([(1, "Linked"), (2, "Also Linked"), (3, "Alone"), (4, "Also Alone")])
        let layout = LinkGraphLayout.make(graph: graph([(1, 2)]), titles: names)

        #expect(layout.nodes.count == 2)
        #expect(layout.unlinkedCount == 2)
    }

    @Test("A link to a note that does not exist is counted as unresolved")
    func unresolvedTitlesAreCounted() {
        let names = titles([(1, "Source"), (2, "Target")])
        let layout = LinkGraphLayout.make(
            graph: graph([(1, 2)], unresolved: [1: ["Somewhere", "Elsewhere"]]),
            titles: names
        )

        #expect(layout.unresolvedCount == 2)
    }

    @Test("A node states what it links to and what links to it")
    func nodesCarryTheirNeighboursNames() throws {
        let names = titles([(1, "Ledger"), (2, "Journal"), (3, "Index")])
        let layout = LinkGraphLayout.make(graph: graph([(1, 2), (3, 1)]), titles: names)

        let ledger = try #require(layout.nodes.first { $0.id == Self.id(1) })
        #expect(ledger.linkedTo == ["Journal"])
        #expect(ledger.linkedFrom == ["Index"])
    }

    @Test("A tap lands on the nearest node, and on nothing at all in open paper")
    func hitTestingFindsTheNearestNode() throws {
        let names = titles([(1, "Hub"), (2, "A"), (3, "B")])
        let layout = LinkGraphLayout.make(graph: graph([(2, 1), (3, 1)]), titles: names)
        let hub = try #require(layout.nodes.first { $0.ring == 0 })

        let near = CGPoint(x: 0.51, y: 0.49)
        #expect(layout.node(nearestTo: near, within: 0.05)?.id == hub.id)
        #expect(layout.node(nearestTo: near, within: 0.001) == nil)
    }

    @Test("An empty library lays out to nothing rather than to a division by zero")
    func emptyGraphIsEmpty() {
        let layout = LinkGraphLayout.make(graph: LinkGraph(), titles: [:])

        #expect(layout == .empty)
        #expect(layout.node(nearestTo: CGPoint(x: 0.5, y: 0.5), within: 1) == nil)
    }
}
