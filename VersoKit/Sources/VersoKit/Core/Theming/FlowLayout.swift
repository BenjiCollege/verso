import SwiftUI

/// Lays children left to right, wrapping to a new line when the next one would
/// not fit.
///
/// Tags need this and nothing in SwiftUI provides it. The alternatives are a
/// horizontal `ScrollView`, which hides the tags you have behind a swipe, or a
/// `Grid`, which forces every tag to the width of the longest — and a tag is as
/// wide as its word.
/// `SwiftUI.Layout` spelled out: this project has a `Layout` of its own — the
/// spacing and radius tokens — and the bare name resolves to that one, which is
/// an enum and cannot be inherited from. Same collision as `Tag`.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = arrange(subviews: subviews, inWidth: width)

        let height = rows.reduce(into: CGFloat.zero) { total, row in
            total += row.height + (total > 0 ? spacing : 0)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout ()
    ) {
        var y = bounds.minY

        for row in arrange(subviews: subviews, inWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    // MARK: - Private

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    /// Which child goes on which line, for a given width.
    ///
    /// Run by both `sizeThatFits` and `placeSubviews`, so the height reported
    /// and the height used are worked out the same way — the usual cause of a
    /// flow layout that clips its last row is two different answers.
    private func arrange(subviews: LayoutSubviews, inWidth width: CGFloat) -> [Row] {
        guard width > 0 else { return [] }

        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = size.width + (current.indices.isEmpty ? 0 : spacing)

            if x + needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                x = 0
            }

            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + (current.indices.count > 1 ? spacing : 0)
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
