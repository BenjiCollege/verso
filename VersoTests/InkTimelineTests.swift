import Foundation
import PencilKit
import Testing
@testable import VersoKit

/// `InkTimeline` is what turns a drawing into a thing that can be replayed and
/// tapped, and it had no tests at all — the one piece of `Core/` that was pure,
/// deterministic logic and entirely uncovered.
@Suite("Ink timeline")
struct InkTimelineTests {

    private let blockID = UUID()
    private let ink = PKInk(.pen, color: .black)

    /// A stroke along a horizontal line, starting at `creationDate`.
    ///
    /// `PKStrokePath` interpolates between control points, so the points read
    /// back out are not the ones put in. Everything asserted below is either a
    /// property of the control points that survives interpolation, or a
    /// relationship rather than an exact interpolated value.
    private func stroke(
        from origin: CGPoint,
        createdAt: Date,
        duration: TimeInterval = 1,
        length: CGFloat = 40
    ) -> PKStroke {
        let points = (0...4).map { step -> PKStrokePoint in
            let fraction = CGFloat(step) / 4
            return PKStrokePoint(
                location: CGPoint(x: origin.x + length * fraction, y: origin.y),
                timeOffset: duration * TimeInterval(fraction),
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: createdAt))
    }

    // MARK: - interval

    @Test("A stroke's interval is measured from the recording, not from itself")
    func intervalIsRelativeToReference() {
        let reference = Date(timeIntervalSince1970: 1_000)
        let drawn = reference.addingTimeInterval(5)

        let interval = InkTimeline.interval(of: stroke(from: .zero, createdAt: drawn), since: reference)

        #expect(interval.start == 5)
        #expect(interval.end >= interval.start)
    }

    @Test("A stroke drawn before the recording began has a negative start")
    func intervalBeforeReferenceIsNegative() {
        let reference = Date(timeIntervalSince1970: 1_000)
        let drawn = reference.addingTimeInterval(-30)

        let interval = InkTimeline.interval(of: stroke(from: .zero, createdAt: drawn), since: reference)

        #expect(interval.start == -30)
    }

    // MARK: - marks

    /// Replaying a stroke that was already on the page as though it arrived in
    /// the first instant would be a lie about the note.
    @Test("Strokes drawn before the recording are dropped, not clamped to zero")
    func marksDropStrokesFromBeforeTheRecording() {
        let reference = Date(timeIntervalSince1970: 1_000)
        let drawing = PKDrawing(strokes: [
            stroke(from: .zero, createdAt: reference.addingTimeInterval(-10)),
            stroke(from: CGPoint(x: 0, y: 100), createdAt: reference.addingTimeInterval(3)),
        ])

        let marks = InkTimeline.marks(in: drawing, blockID: blockID, recordingStartedAt: reference)

        #expect(marks.count == 1)
        #expect(marks.first?.start == 3)
        #expect(marks.allSatisfy { $0.start >= 0 })
    }

    /// The index has to be the stroke's position in the drawing, because that
    /// is what `drawing(_:limitedTo:)` selects on. Dropping an early stroke
    /// must not renumber the ones that survive.
    @Test("A dropped stroke does not renumber the strokes that survive")
    func marksKeepDrawingOrderIndices() {
        let reference = Date(timeIntervalSince1970: 1_000)
        let drawing = PKDrawing(strokes: [
            stroke(from: .zero, createdAt: reference.addingTimeInterval(-1)),
            stroke(from: CGPoint(x: 0, y: 100), createdAt: reference.addingTimeInterval(1)),
            stroke(from: CGPoint(x: 0, y: 200), createdAt: reference.addingTimeInterval(2)),
        ])

        let marks = InkTimeline.marks(in: drawing, blockID: blockID, recordingStartedAt: reference)

        #expect(marks.map(\.strokeIndex) == [1, 2])
        #expect(marks.allSatisfy { $0.blockID == blockID })
    }

    @Test("An empty drawing produces no marks")
    func marksFromEmptyDrawing() {
        let marks = InkTimeline.marks(
            in: PKDrawing(),
            blockID: blockID,
            recordingStartedAt: Date(timeIntervalSince1970: 1_000)
        )
        #expect(marks.isEmpty)
    }

    // MARK: - drawing(limitedTo:)

    @Test("Replay keeps only the strokes asked for, in drawing order")
    func limitedDrawingSelectsBySubset() {
        let now = Date(timeIntervalSince1970: 1_000)
        let drawing = PKDrawing(strokes: [
            stroke(from: .zero, createdAt: now),
            stroke(from: CGPoint(x: 0, y: 100), createdAt: now),
            stroke(from: CGPoint(x: 0, y: 200), createdAt: now),
        ])

        #expect(InkTimeline.drawing(drawing, limitedTo: [0, 2]).strokes.count == 2)
        #expect(InkTimeline.drawing(drawing, limitedTo: []).strokes.isEmpty)
        #expect(InkTimeline.drawing(drawing, limitedTo: [0, 1, 2]).strokes.count == 3)
    }

    @Test("An index past the end is ignored rather than trapping")
    func limitedDrawingIgnoresUnknownIndices() {
        let drawing = PKDrawing(strokes: [stroke(from: .zero, createdAt: Date())])
        #expect(InkTimeline.drawing(drawing, limitedTo: [0, 99]).strokes.count == 1)
        #expect(InkTimeline.drawing(drawing, limitedTo: [99]).strokes.isEmpty)
    }

    // MARK: - nearestStrokeIndex

    @Test("A tap finds the stroke nearest it")
    func nearestStrokeFindsTheClosest() {
        let now = Date(timeIntervalSince1970: 1_000)
        let drawing = PKDrawing(strokes: [
            stroke(from: .zero, createdAt: now),
            stroke(from: CGPoint(x: 0, y: 500), createdAt: now),
        ])

        #expect(InkTimeline.nearestStrokeIndex(to: CGPoint(x: 10, y: 0), in: drawing) == 0)
        #expect(InkTimeline.nearestStrokeIndex(to: CGPoint(x: 10, y: 500), in: drawing) == 1)
    }

    /// Tapping bare paper has to mean "nothing", not "the least distant thing
    /// on the page" — otherwise a tap anywhere seeks playback somewhere.
    @Test("A tap far from any stroke finds nothing")
    func nearestStrokeRespectsTolerance() {
        let drawing = PKDrawing(strokes: [stroke(from: .zero, createdAt: Date())])
        #expect(InkTimeline.nearestStrokeIndex(to: CGPoint(x: 10, y: 4_000), in: drawing) == nil)
    }

    @Test("An empty drawing has no nearest stroke")
    func nearestStrokeInEmptyDrawing() {
        #expect(InkTimeline.nearestStrokeIndex(to: .zero, in: PKDrawing()) == nil)
    }

    // MARK: - preferredHeight

    @Test("An empty drawing keeps the minimum height rather than collapsing")
    func preferredHeightOfEmptyDrawing() {
        #expect(InkTimeline.preferredHeight(for: PKDrawing()) == SketchPayload.minimumHeight)
    }

    @Test("A block grows with its content, and stops at the maximum")
    func preferredHeightGrowsAndClamps() {
        let now = Date(timeIntervalSince1970: 1_000)

        let shallow = PKDrawing(strokes: [stroke(from: CGPoint(x: 0, y: 20), createdAt: now)])
        #expect(InkTimeline.preferredHeight(for: shallow) == SketchPayload.minimumHeight)

        let tall = PKDrawing(strokes: [stroke(from: CGPoint(x: 0, y: 600), createdAt: now)])
        let height = InkTimeline.preferredHeight(for: tall)
        #expect(height > SketchPayload.minimumHeight)
        #expect(height <= SketchPayload.maximumHeight)

        let enormous = PKDrawing(strokes: [stroke(from: CGPoint(x: 0, y: 9_000), createdAt: now)])
        #expect(InkTimeline.preferredHeight(for: enormous) == SketchPayload.maximumHeight)
    }
}
