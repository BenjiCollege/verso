import Foundation

/// What was on the page at each moment of a recording.
///
/// Two streams, per section 7: typed text as `(characterOffset, timestamp)`
/// pairs, and ink as stroke intervals taken from `PKStroke`'s own per-point
/// timestamps. Both are stored as plain values with no framework types, so the
/// seeking arithmetic — which is where an off-by-one becomes "tapping a word
/// plays the wrong sentence" — is testable on its own.
struct SyncMap: Codable, Hashable, Sendable {

    /// Where the caret was, and when.
    struct TextMark: Codable, Hashable, Sendable, Comparable {
        var blockID: UUID
        /// UTF-16 offset within that block, matching everything else that
        /// speaks to `UITextView`.
        var characterOffset: Int
        /// Seconds from the start of the recording.
        var time: TimeInterval

        static func < (lhs: TextMark, rhs: TextMark) -> Bool { lhs.time < rhs.time }
    }

    /// When a stroke was drawn.
    struct StrokeMark: Codable, Hashable, Sendable, Comparable {
        var blockID: UUID
        /// Index into the drawing's stroke array, which is its draw order.
        var strokeIndex: Int
        var start: TimeInterval
        var end: TimeInterval

        static func < (lhs: StrokeMark, rhs: StrokeMark) -> Bool { lhs.start < rhs.start }
    }

    /// Sorted by time.
    var textMarks: [TextMark]
    /// Sorted by start.
    var strokeMarks: [StrokeMark]
    var duration: TimeInterval

    init(textMarks: [TextMark] = [], strokeMarks: [StrokeMark] = [], duration: TimeInterval = 0) {
        self.textMarks = textMarks.sorted()
        self.strokeMarks = strokeMarks.sorted()
        self.duration = duration
    }

    var isEmpty: Bool { textMarks.isEmpty && strokeMarks.isEmpty }

    // MARK: - Seeking by position

    /// When a given point in the text was written.
    ///
    /// Uses the latest mark at or before the offset in that block. Typing is
    /// sampled, not recorded per character, so a tapped word almost never has a
    /// mark of its own — the nearest earlier one is the honest answer.
    func time(forCharacterOffset offset: Int, in blockID: UUID) -> TimeInterval? {
        let candidates = textMarks.filter { $0.blockID == blockID && $0.characterOffset <= offset }
        guard let best = candidates.max(by: { $0.characterOffset < $1.characterOffset }) else {
            // Nothing earlier in this block: fall back to the first mark it has,
            // which is when the block was started.
            return textMarks.first { $0.blockID == blockID }?.time
        }
        return best.time
    }

    func time(forStrokeIndex index: Int, in blockID: UUID) -> TimeInterval? {
        strokeMarks.first { $0.blockID == blockID && $0.strokeIndex == index }?.start
    }

    // MARK: - Seeking by time

    /// Where the caret was at a given moment.
    func mark(at time: TimeInterval) -> TextMark? {
        var result: TextMark?
        for mark in textMarks {
            guard mark.time <= time else { break }
            result = mark
        }
        return result
    }

    /// Strokes that had been drawn by a given moment.
    ///
    /// A stroke counts once it has *finished*, so replay draws whole strokes
    /// rather than growing ones — partial strokes would need per-point
    /// interpolation and would look like a glitch, not like writing.
    func strokeIndices(visibleAt time: TimeInterval, in blockID: UUID) -> [Int] {
        strokeMarks
            .filter { $0.blockID == blockID && $0.end <= time }
            .map(\.strokeIndex)
    }

    /// How much of a block's text had been typed by a given moment.
    func characterCount(visibleAt time: TimeInterval, in blockID: UUID) -> Int? {
        var result: Int?
        for mark in textMarks where mark.blockID == blockID {
            guard mark.time <= time else { break }
            result = mark.characterOffset
        }
        return result
    }

    /// Every block the recording touched, in the order it first touched them.
    var blockIDs: [UUID] {
        var seen = Set<UUID>()
        let fromText = textMarks.map(\.blockID)
        let fromInk = strokeMarks.map(\.blockID)
        return (fromText + fromInk).filter { seen.insert($0).inserted }
    }
}

/// Builds a sync map while a recording is running.
///
/// Text samples arrive on every keystroke; section 7 asks for them to be
/// coalesced on commit, and this is where that happens. Without it a minute of
/// typing is several thousand marks, most of which say the same thing as the
/// one before.
struct SyncMapRecorder: Sendable {

    /// Minimum gap between kept marks. Four a second is finer than anyone can
    /// tap, and two orders of magnitude fewer than one per keystroke.
    var minimumInterval: TimeInterval = 0.25

    private(set) var textMarks: [SyncMap.TextMark] = []
    private(set) var strokeMarks: [SyncMap.StrokeMark] = []

    init(minimumInterval: TimeInterval = 0.25) {
        self.minimumInterval = minimumInterval
    }

    /// Records where the caret is, unless it is too soon after the last one in
    /// the same block.
    mutating func sample(blockID: UUID, characterOffset: Int, at time: TimeInterval) {
        if let last = textMarks.last(where: { $0.blockID == blockID }) {
            guard time - last.time >= minimumInterval else {
                // Still worth keeping the furthest point reached in this window,
                // or a fast typist's marks all point at where they started.
                if characterOffset > last.characterOffset,
                   let index = textMarks.lastIndex(where: { $0.blockID == blockID }) {
                    textMarks[index].characterOffset = characterOffset
                }
                return
            }
        }
        textMarks.append(.init(blockID: blockID, characterOffset: characterOffset, time: time))
    }

    mutating func record(strokes: [SyncMap.StrokeMark]) {
        // Replaced rather than appended: a drawing is re-read whole each time,
        // and appending would duplicate every stroke on every sample.
        let others = strokeMarks.filter { mark in !strokes.contains { $0.blockID == mark.blockID } }
        strokeMarks = (others + strokes).sorted()
    }

    func map(duration: TimeInterval) -> SyncMap {
        SyncMap(textMarks: textMarks, strokeMarks: strokeMarks, duration: duration)
    }
}

extension SyncMap {
    static func decode(_ data: Data) -> SyncMap? {
        guard !data.isEmpty else { return nil }
        return try? BlockCoding.decode(SyncMap.self, from: data)
    }

    func encoded() throws -> Data {
        try BlockCoding.encode(self)
    }
}
