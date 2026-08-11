import CoreGraphics
import Foundation

/// What the fore-edge looks like, derived from the note and the theme.
///
/// Pure. The strip is the one bold thing in the app, so how it is generated is
/// worth being able to reason about without a screenshot.
struct ForeEdgeModel: Equatable, Sendable {

    /// How the leaves are drawn. Section 6: the pattern encodes the active
    /// theme, so this comes from the theme's identifier rather than from a
    /// setting — two notes in the same theme have the same edge, and switching
    /// theme re-cuts the block.
    enum Pattern: Int, CaseIterable, Sendable {
        case solid
        case ticked
        case dashed
        case gilded
        case marbled
    }

    /// One drawn leaf.
    struct Leaf: Equatable, Sendable {
        /// 0...1 down the strip.
        var position: Double
        /// 0...1, how far across the strip it reaches.
        var extent: Double
        /// 0...1. Gilded and marbled patterns vary this per leaf.
        var emphasis: Double
    }

    var leaves: [Leaf]
    var pattern: Pattern
    var isLocked: Bool

    /// A note has to be reasonably long before the edge reads as a block of
    /// pages rather than a few scratches.
    static let minimumLeaves = 6
    static let maximumLeaves = 96

    /// Characters per leaf. Chosen so a page of prose is a few leaves and a
    /// twenty-thousand-word note fills the strip.
    static let charactersPerLeaf = 220

    /// Deterministic across launches and devices, unlike `Hashable`'s hashing,
    /// which is seeded per process. Two devices showing the same note must cut
    /// the same edge.
    static func patternIndex(forThemeID id: String) -> Pattern {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let index = Int(hash % UInt64(Pattern.allCases.count))
        return Pattern(rawValue: index) ?? .solid
    }

    /// Builds the edge for a note of a given length.
    ///
    /// Leaf count encodes length, and the leaves are jittered deterministically
    /// so the block looks cut rather than printed — but the same note always
    /// produces the same edge.
    static func make(
        readableLength: Int,
        themeID: String,
        isLocked: Bool
    ) -> ForeEdgeModel {
        let pattern = patternIndex(forThemeID: themeID)

        let raw = max(1, readableLength) / charactersPerLeaf
        let count = min(max(raw + minimumLeaves, minimumLeaves), maximumLeaves)

        var seed = UInt64(truncatingIfNeeded: readableLength &+ 0x9E37_79B9) | 1
        func nextUnit() -> Double {
            // xorshift64 — deterministic, and quality is irrelevant for jitter.
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 1000) / 1000
        }

        let leaves = (0..<count).map { index -> Leaf in
            let position = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let jitter = nextUnit()

            let extent: Double = switch pattern {
            case .solid: 1.0
            case .ticked: index.isMultiple(of: 4) ? 1.0 : 0.55
            case .dashed: index.isMultiple(of: 2) ? 0.9 : 0.3
            case .gilded: 0.7 + jitter * 0.3
            case .marbled: 0.45 + jitter * 0.55
            }

            let emphasis: Double = switch pattern {
            case .solid: 0.5
            case .ticked: index.isMultiple(of: 4) ? 1.0 : 0.35
            case .dashed: 0.6
            case .gilded: index.isMultiple(of: 8) ? 1.0 : jitter * 0.5
            case .marbled: jitter
            }

            return Leaf(position: position, extent: extent, emphasis: emphasis)
        }

        return ForeEdgeModel(leaves: leaves, pattern: pattern, isLocked: isLocked)
    }
}

/// Maps a drag along the fore-edge onto a point in the note's history.
///
/// Pure, because getting this wrong is the difference between the signature
/// interaction feeling like a scrubber and feeling like a bug, and none of it
/// can be checked by looking at a screenshot.
struct ForeEdgeScrubber: Equatable, Sendable {

    /// How far down the strip the drag must travel before scrubbing starts.
    /// Below this, a touch on the edge is a touch, not a scrub.
    var activationDistance: CGFloat = 12

    /// Fraction of the strip's height given over to the present. Makes it easy
    /// to land back on "now" without hunting for the exact top.
    var presentZone: Double = 0.06

    /// Downwards travel goes backwards in time: the top of the strip is now and
    /// the bottom is the oldest version kept.
    ///
    /// - Returns: an index into a newest-first version list, or `nil` for the
    ///   present.
    func versionIndex(atY y: CGFloat, height: CGFloat, versionCount: Int) -> Int? {
        guard versionCount > 0, height > 0 else { return nil }

        let fraction = min(max(Double(y / height), 0), 1)
        guard fraction > presentZone else { return nil }

        let scaled = (fraction - presentZone) / (1 - presentZone)
        let index = Int((scaled * Double(versionCount)).rounded(.down))
        return min(index, versionCount - 1)
    }

    /// The inverse, for drawing the thumb at the right height.
    func y(forVersionIndex index: Int?, height: CGFloat, versionCount: Int) -> CGFloat {
        guard let index, versionCount > 0 else { return 0 }
        let scaled = (Double(index) + 0.5) / Double(versionCount)
        return CGFloat((presentZone + scaled * (1 - presentZone))) * height
    }

    func shouldActivate(translation: CGSize) -> Bool {
        abs(translation.height) >= activationDistance
    }

    /// Points per second, for modulating the scrub haptic.
    func velocity(from previous: (y: CGFloat, time: TimeInterval)?, to current: (y: CGFloat, time: TimeInterval)) -> CGFloat {
        guard let previous else { return 0 }
        let elapsed = current.time - previous.time
        guard elapsed > 0.0001 else { return 0 }
        return (current.y - previous.y) / CGFloat(elapsed)
    }
}
