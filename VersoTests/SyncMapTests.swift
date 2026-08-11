import AVFoundation
import Foundation
import Testing
@testable import VersoKit

@Suite("Sync map")
struct SyncMapTests {

    private let blockA = UUID()
    private let blockB = UUID()

    private func map(
        _ text: [(Int, TimeInterval)] = [],
        block: UUID? = nil,
        strokes: [(Int, TimeInterval, TimeInterval)] = [],
        duration: TimeInterval = 60
    ) -> SyncMap {
        let id = block ?? blockA
        return SyncMap(
            textMarks: text.map { .init(blockID: id, characterOffset: $0.0, time: $0.1) },
            strokeMarks: strokes.map { .init(blockID: id, strokeIndex: $0.0, start: $0.1, end: $0.2) },
            duration: duration
        )
    }

    // MARK: - Position to time

    /// Tapping a word has to land on when it was written, and typing is sampled
    /// rather than recorded per character — so the nearest earlier mark is the
    /// honest answer.
    @Test("An offset resolves to the latest mark at or before it")
    func offsetFindsPrecedingMark() {
        let map = map([(0, 0), (20, 5), (60, 12)])

        #expect(map.time(forCharacterOffset: 0, in: blockA) == 0)
        #expect(map.time(forCharacterOffset: 25, in: blockA) == 5)
        #expect(map.time(forCharacterOffset: 60, in: blockA) == 12)
        #expect(map.time(forCharacterOffset: 999, in: blockA) == 12)
    }

    @Test("An offset before the first mark falls back to when the block started")
    func offsetBeforeFirstMark() {
        let map = map([(10, 4), (30, 9)])
        #expect(map.time(forCharacterOffset: 2, in: blockA) == 4)
    }

    @Test("A block the recording never touched has no time")
    func unknownBlockHasNoTime() {
        #expect(map([(0, 0)]).time(forCharacterOffset: 5, in: blockB) == nil)
    }

    @Test("Marks in one block do not answer for another")
    func blocksAreIndependent() {
        let combined = SyncMap(textMarks: [
            .init(blockID: blockA, characterOffset: 0, time: 1),
            .init(blockID: blockB, characterOffset: 0, time: 10),
        ])
        #expect(combined.time(forCharacterOffset: 0, in: blockA) == 1)
        #expect(combined.time(forCharacterOffset: 0, in: blockB) == 10)
    }

    @Test("A stroke resolves to when it started")
    func strokeFindsItsTime() {
        let map = map(strokes: [(0, 2, 3), (1, 8, 9)])
        #expect(map.time(forStrokeIndex: 1, in: blockA) == 8)
        #expect(map.time(forStrokeIndex: 9, in: blockA) == nil)
    }

    // MARK: - Time to position

    @Test("A moment resolves to where the caret was")
    func timeFindsCaret() {
        let map = map([(0, 0), (20, 5), (60, 12)])

        #expect(map.mark(at: 0)?.characterOffset == 0)
        #expect(map.mark(at: 7)?.characterOffset == 20)
        #expect(map.mark(at: 99)?.characterOffset == 60)
    }

    @Test("A moment before the recording started has no position")
    func beforeTheStart() {
        #expect(map([(0, 1)]).mark(at: 0.5) == nil)
    }

    /// Replay draws whole strokes, not growing ones — a partial stroke would
    /// look like a glitch rather than like writing.
    @Test("Only strokes that had finished are visible")
    func strokesAppearWhenTheyFinish() {
        let map = map(strokes: [(0, 0, 2), (1, 3, 5), (2, 6, 9)])

        #expect(map.strokeIndices(visibleAt: 1, in: blockA).isEmpty)
        #expect(map.strokeIndices(visibleAt: 2, in: blockA) == [0])
        #expect(map.strokeIndices(visibleAt: 5.5, in: blockA) == [0, 1])
        #expect(map.strokeIndices(visibleAt: 100, in: blockA) == [0, 1, 2])
    }

    @Test("How much text had been typed at a moment")
    func characterCountOverTime() {
        let map = map([(0, 0), (20, 5), (60, 12)])

        #expect(map.characterCount(visibleAt: 0, in: blockA) == 0)
        #expect(map.characterCount(visibleAt: 6, in: blockA) == 20)
        #expect(map.characterCount(visibleAt: 30, in: blockA) == 60)
    }

    @Test("Both streams contribute to the list of blocks touched")
    func blockIDsCoverBothStreams() {
        let combined = SyncMap(
            textMarks: [.init(blockID: blockA, characterOffset: 0, time: 0)],
            strokeMarks: [.init(blockID: blockB, strokeIndex: 0, start: 1, end: 2)]
        )
        #expect(Set(combined.blockIDs) == [blockA, blockB])
    }

    @Test("Marks are sorted however they arrive")
    func marksAreSorted() {
        let unsorted = SyncMap(textMarks: [
            .init(blockID: blockA, characterOffset: 30, time: 9),
            .init(blockID: blockA, characterOffset: 0, time: 1),
        ])
        #expect(unsorted.textMarks.map(\.time) == [1, 9])
    }

    @Test("An empty map answers nothing rather than trapping")
    func emptyMapIsSafe() {
        let empty = SyncMap()
        #expect(empty.isEmpty)
        #expect(empty.mark(at: 5) == nil)
        #expect(empty.time(forCharacterOffset: 0, in: blockA) == nil)
        #expect(empty.strokeIndices(visibleAt: 5, in: blockA).isEmpty)
    }

    @Test("A map survives being stored on the asset")
    func codingRoundTrips() throws {
        let original = map([(0, 0), (20, 5)], strokes: [(0, 1, 2)])
        #expect(SyncMap.decode(try original.encoded()) == original)
        #expect(SyncMap.decode(Data()) == nil)
    }
}

@Suite("Sync map recording")
struct SyncMapRecorderTests {

    private let block = UUID()

    /// A minute of typing is several thousand samples, most saying the same
    /// thing as the one before. Section 7 asks for them coalesced on commit.
    @Test("Samples closer than the interval are coalesced")
    func samplesAreCoalesced() {
        var recorder = SyncMapRecorder(minimumInterval: 0.25)

        for step in 0..<100 {
            recorder.sample(blockID: block, characterOffset: step, at: Double(step) * 0.01)
        }

        // A second of typing at 100Hz, kept at four a second: 100 samples in,
        // marks at 0, 0.25, 0.5 and 0.75 out.
        #expect(recorder.textMarks.count == 4)
    }

    /// Coalescing must not throw away where the typist reached, or every mark
    /// points at where they started.
    @Test("A coalesced mark keeps the furthest offset reached")
    func coalescingKeepsProgress() {
        var recorder = SyncMapRecorder(minimumInterval: 0.25)
        recorder.sample(blockID: block, characterOffset: 0, at: 0)
        recorder.sample(blockID: block, characterOffset: 12, at: 0.1)
        recorder.sample(blockID: block, characterOffset: 25, at: 0.2)

        #expect(recorder.textMarks.count == 1)
        #expect(recorder.textMarks[0].characterOffset == 25)
        #expect(recorder.textMarks[0].time == 0)
    }

    @Test("Samples past the interval become their own marks")
    func spacedSamplesAreKept() {
        var recorder = SyncMapRecorder(minimumInterval: 0.25)
        recorder.sample(blockID: block, characterOffset: 0, at: 0)
        recorder.sample(blockID: block, characterOffset: 10, at: 1)
        recorder.sample(blockID: block, characterOffset: 20, at: 2)

        #expect(recorder.textMarks.count == 3)
    }

    @Test("Each block is coalesced separately")
    func blocksCoalesceIndependently() {
        var recorder = SyncMapRecorder(minimumInterval: 0.25)
        let other = UUID()

        recorder.sample(blockID: block, characterOffset: 0, at: 0)
        recorder.sample(blockID: other, characterOffset: 0, at: 0.05)

        #expect(recorder.textMarks.count == 2)
    }

    /// A drawing is re-read whole on every change, so appending would duplicate
    /// every stroke on every sample.
    @Test("Re-recording a block's strokes replaces rather than appends")
    func strokesAreReplaced() {
        var recorder = SyncMapRecorder()
        let marks = [
            SyncMap.StrokeMark(blockID: block, strokeIndex: 0, start: 1, end: 2),
            SyncMap.StrokeMark(blockID: block, strokeIndex: 1, start: 3, end: 4),
        ]

        recorder.record(strokes: [marks[0]])
        recorder.record(strokes: marks)

        #expect(recorder.strokeMarks.count == 2)
    }

    @Test("Strokes from different blocks coexist")
    func strokesFromDifferentBlocks() {
        var recorder = SyncMapRecorder()
        let other = UUID()

        recorder.record(strokes: [.init(blockID: block, strokeIndex: 0, start: 1, end: 2)])
        recorder.record(strokes: [.init(blockID: other, strokeIndex: 0, start: 3, end: 4)])

        #expect(recorder.strokeMarks.count == 2)
    }

    @Test("The finished map carries the recording's length")
    func mapCarriesDuration() {
        var recorder = SyncMapRecorder()
        recorder.sample(blockID: block, characterOffset: 0, at: 0)
        #expect(recorder.map(duration: 42).duration == 42)
    }
}

@Suite("Ink and audio payloads")
struct InkAudioPayloadTests {

    @Test("Sketch payload survives encode/decode")
    func sketchRoundTrip() throws {
        let original = SketchPayload(drawing: Data([0x01, 0x02]), height: 240, recordedWith: UUID())
        #expect(try BlockCoding.decode(SketchPayload.self, from: BlockCoding.encode(original)) == original)
    }

    @Test("Sketch height is clamped to something drawable")
    func sketchHeightClamps() {
        #expect(SketchPayload(height: 10).height == SketchPayload.minimumHeight)
        #expect(SketchPayload(height: 99_999).height == SketchPayload.maximumHeight)
    }

    /// A template carries the shape of a note, not somebody's drawing or voice.
    @Test("Templates keep the shape and drop the content")
    func templateResets() {
        let sketch = SketchPayload(drawing: Data([0x01]), height: 300).resetForTemplate()
        #expect(sketch.drawing.isEmpty)
        #expect(sketch.height == 300)

        let audio = AudioPayload(assetID: UUID(), label: "Interview").resetForTemplate()
        #expect(audio.assetID == nil)
        #expect(audio.label == "Interview")
    }

    @Test("Audio payload survives encode/decode")
    func audioRoundTrip() throws {
        let original = AudioPayload(assetID: UUID(), label: "Standup")
        #expect(try BlockCoding.decode(AudioPayload.self, from: BlockCoding.encode(original)) == original)
    }

    /// A dead link to a file that did not come along would be worse than
    /// saying so.
    @Test("Markdown export is honest that audio cannot come along")
    func audioMarkdownIsHonest() {
        let markdown = AudioPayload(assetID: UUID(), label: "Standup").markdownRepresentation
        #expect(markdown.contains("Standup"))
        #expect(markdown.lowercased().contains("not included"))
    }

    @Test("An empty sketch contributes nothing to an export")
    func emptySketchExportsNothing() {
        #expect(SketchPayload().markdownRepresentation.isEmpty)
        #expect(!SketchPayload(drawing: Data([0x01])).markdownRepresentation.isEmpty)
    }

    @Test("Recording format is AAC mono at 32kbps, per section 7")
    func recordingFormat() {
        #expect(AudioStore.settings[AVEncoderBitRateKey] as? Int == 32_000)
        #expect(AudioStore.settings[AVNumberOfChannelsKey] as? Int == 1)
    }
}
