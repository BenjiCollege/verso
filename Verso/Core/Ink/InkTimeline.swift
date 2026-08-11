import Foundation
import PencilKit

/// Reading time out of ink.
///
/// `PKStroke` carries a creation date and each of its points carries an offset
/// from it, which means a drawing already knows when it was drawn. Section 7's
/// requirement to replay ink as it was written needs no extra bookkeeping —
/// only this conversion into the recording's own clock.
enum InkTimeline {

    /// Turns a drawing into stroke intervals relative to a recording's start.
    ///
    /// Strokes drawn before the recording began are dropped rather than
    /// clamped to zero: they were already on the page, and replaying them as
    /// though they arrived in the first instant would be a lie about the note.
    static func marks(
        in drawing: PKDrawing,
        blockID: UUID,
        recordingStartedAt: Date
    ) -> [SyncMap.StrokeMark] {
        drawing.strokes.enumerated().compactMap { index, stroke in
            let interval = self.interval(of: stroke, since: recordingStartedAt)
            guard interval.start >= 0 else { return nil }
            return SyncMap.StrokeMark(
                blockID: blockID,
                strokeIndex: index,
                start: interval.start,
                end: interval.end
            )
        }
    }

    /// When a stroke started and finished, in seconds from a reference date.
    static func interval(of stroke: PKStroke, since reference: Date) -> (start: TimeInterval, end: TimeInterval) {
        let start = stroke.path.creationDate.timeIntervalSince(reference)
        let last = stroke.path.last?.timeOffset ?? 0
        return (start, start + last)
    }

    /// A drawing containing only the strokes drawn by a given moment.
    ///
    /// Used by replay. Rebuilding a `PKDrawing` from a stroke subset is cheap
    /// and keeps every stroke's own appearance — the alternative, drawing paths
    /// by hand, loses the ink's texture and the whole point of PencilKit.
    static func drawing(_ drawing: PKDrawing, limitedTo indices: [Int]) -> PKDrawing {
        let wanted = Set(indices)
        let strokes = drawing.strokes.enumerated()
            .filter { wanted.contains($0.offset) }
            .map(\.element)
        return PKDrawing(strokes: strokes)
    }

    /// The stroke nearest a point, for tapping ink to seek playback.
    ///
    /// Distance is measured to the stroke's own points rather than to its
    /// bounding box, so a tap inside the loop of a large letter finds the
    /// letter and not whatever else overlaps that rectangle.
    static func nearestStrokeIndex(
        to point: CGPoint,
        in drawing: PKDrawing,
        within tolerance: CGFloat = 44
    ) -> Int? {
        var best: (index: Int, distance: CGFloat)?

        for (index, stroke) in drawing.strokes.enumerated() {
            guard stroke.renderBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }

            for strokePoint in stroke.path {
                let dx = strokePoint.location.x - point.x
                let dy = strokePoint.location.y - point.y
                let distance = (dx * dx + dy * dy).squareRoot()
                if best == nil || distance < best!.distance {
                    best = (index, distance)
                }
            }
        }

        guard let best, best.distance <= tolerance else { return nil }
        return best.index
    }

    /// A drawing's natural height, so a sketch block can grow with its content.
    static func preferredHeight(for drawing: PKDrawing, minimum: Double = SketchPayload.minimumHeight) -> Double {
        guard !drawing.bounds.isNull, !drawing.bounds.isEmpty else { return minimum }
        return min(max(Double(drawing.bounds.maxY) + 48, minimum), SketchPayload.maximumHeight)
    }
}
