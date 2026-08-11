import Foundation
import Testing
@testable import VersoKit

@Suite("Data block payloads")
struct DataBlockPayloadTests {

    @Test("Metric payload survives encode/decode")
    func metricRoundTrip() throws {
        let original = MetricPayload(
            label: "Bench press",
            value: 82.5,
            unit: "kg",
            target: 100,
            seriesID: "bench-press",
            groupID: "set-2"
        )
        #expect(try BlockCoding.decode(MetricPayload.self, from: BlockCoding.encode(original)) == original)
    }

    /// An unfilled metric is not a measurement of zero, and a chart must not
    /// treat it as one.
    @Test("An empty metric round-trips as empty, not as zero")
    func emptyMetricStaysEmpty() throws {
        let original = MetricPayload(label: "Bodyweight", unit: "kg", seriesID: "bodyweight")
        let restored = try BlockCoding.decode(MetricPayload.self, from: BlockCoding.encode(original))
        #expect(restored.value == nil)
        #expect(restored.fractionOfTarget == nil)
    }

    @Test("Metric progress against a target")
    func metricTargetFraction() {
        #expect(MetricPayload(value: 50, target: 200).fractionOfTarget == 0.25)
        #expect(MetricPayload(value: 50, target: 0).fractionOfTarget == nil)
        #expect(MetricPayload(target: 200).fractionOfTarget == nil)
    }

    @Test("Timer payload survives encode/decode", arguments: TimerPayload.Sound.allCases)
    func timerRoundTrip(sound: TimerPayload.Sound) throws {
        let original = TimerPayload(label: "Rest", duration: 90, autoStart: true, sound: sound)
        #expect(try BlockCoding.decode(TimerPayload.self, from: BlockCoding.encode(original)) == original)
    }

    @Test("A zero or negative duration is clamped to something startable")
    func timerDurationClamps() throws {
        let data = Data(#"{"duration":0}"#.utf8)
        #expect(try BlockCoding.decode(TimerPayload.self, from: data).duration == 1)
    }

    @Test("Durations format for both the dial and VoiceOver", arguments: [
        (0.0, "0:00"),
        (5.0, "0:05"),
        (90.0, "1:30"),
        (600.0, "10:00"),
        (3661.0, "1:01:01"),
    ])
    func clockFormatting(duration: TimeInterval, expected: String) {
        #expect(duration.timerClockText == expected)
    }

    @Test("Formula payload survives encode/decode")
    func formulaRoundTrip() throws {
        let original = FormulaPayload(label: "Total", expression: "sum(subtotal)")
        #expect(try BlockCoding.decode(FormulaPayload.self, from: BlockCoding.encode(original)) == original)
    }

    @Test("Progress payload survives encode/decode", arguments: ProgressPayload.Style.allCases)
    func progressRoundTrip(style: ProgressPayload.Style) throws {
        let original = ProgressPayload(label: "Water", current: 4, target: 8, style: style)
        #expect(try BlockCoding.decode(ProgressPayload.self, from: BlockCoding.encode(original)) == original)
    }

    /// Overshooting a target is worth celebrating, not worth drawing a bar past
    /// the end of itself.
    @Test("Progress clamps to 0...1 but still reports completion")
    func progressClamps() {
        #expect(ProgressPayload(current: 12, target: 8).fraction == 1)
        #expect(ProgressPayload(current: 12, target: 8).isComplete)
        #expect(ProgressPayload(current: -4, target: 8).fraction == 0)
        #expect(ProgressPayload(current: 4, target: 0).fraction == 0)
        #expect(!ProgressPayload(current: 4, target: 0).isComplete)
    }

    @Test("Rating payload survives encode/decode", arguments: RatingPayload.Symbol.allCases)
    func ratingRoundTrip(symbol: RatingPayload.Symbol) throws {
        let original = RatingPayload(label: "Sleep", scale: 5, value: 4, symbol: symbol)
        #expect(try BlockCoding.decode(RatingPayload.self, from: BlockCoding.encode(original)) == original)
    }

    @Test("Rating scale and value are clamped to something usable")
    func ratingClamps() {
        #expect(RatingPayload(scale: 1).scale == 2)
        #expect(RatingPayload(scale: 100).scale == 10)
        #expect(RatingPayload(scale: 5, value: 9).value == 5)
        #expect(RatingPayload(scale: 5, value: -1).value == 0)
        #expect(RatingPayload(scale: 5).value == nil, "unrated is not the same as rated zero")
    }

    @Test("Table payload survives encode/decode")
    func tableRoundTrip() throws {
        let columns = [
            TablePayload.Column(title: "Exercise", kind: .text),
            TablePayload.Column(title: "Weight", kind: .number),
            TablePayload.Column(title: "Done", kind: .checkbox),
        ]
        let original = TablePayload(
            caption: "Session",
            columns: columns,
            rows: [
                .init(cells: [.init(text: "Squat"), .init(number: 100), .init(checked: true)]),
                .init(cells: [.init(text: "Bench"), .init(number: 80), .init(checked: false)]),
            ]
        )
        #expect(try BlockCoding.decode(TablePayload.self, from: BlockCoding.encode(original)) == original)
    }

    /// A ragged table from a hand-written template, or a column added on
    /// another device, has to land somewhere other than an index crash.
    @Test("Ragged rows are padded and over-long rows trimmed on decode")
    func tableNormalisesOnDecode() throws {
        let data = Data("""
        {"columns":[{"title":"A"},{"title":"B"}],"rows":[{"cells":[]},{"cells":[{"text":"1"},{"text":"2"},{"text":"3"}]}]}
        """.utf8)
        let payload = try BlockCoding.decode(TablePayload.self, from: data)

        #expect(payload.rows.allSatisfy { $0.cells.count == 2 })
        #expect(payload.rows[1].cells.map(\.text) == ["1", "2"])
    }

    /// Changing a column's type must not throw away what was typed under the
    /// old one, in case the user changes it back.
    @Test("A cell keeps every representation regardless of column type")
    func cellKeepsAllRepresentations() throws {
        let cell = TablePayload.Cell(text: "12", number: 12, checked: true)
        let restored = try BlockCoding.decode(TablePayload.Cell.self, from: BlockCoding.encode(cell))

        #expect(restored == cell)
        #expect(restored.display(for: .text) == "12")
        #expect(restored.display(for: .number) == "12")
        #expect(restored.display(for: .checkbox) == "✓")
    }

    @Test("A table column reads out as numbers for formulas")
    func tableColumnNumbers() {
        let payload = TablePayload(
            columns: [
                .init(title: "Exercise", kind: .text),
                .init(title: "Weight", kind: .number),
                .init(title: "Done", kind: .checkbox),
            ],
            rows: [
                .init(cells: [.init(text: "Squat"), .init(number: 100), .init(checked: true)]),
                .init(cells: [.init(text: "Bench"), .init(number: 80), .init(checked: false)]),
            ]
        )

        #expect(payload.numbers(inColumnTitled: "Weight") == [100, 80])
        #expect(payload.numbers(inColumnTitled: "  weight ") == [100, 80], "matching a column ignores case and space")
        #expect(payload.numbers(inColumnTitled: "Done") == [1, 0])
        #expect(payload.numbers(inColumnTitled: "Missing").isEmpty)
    }

    @Test("Unknown enum values in data blocks degrade rather than throw")
    func unknownEnumsDegrade() throws {
        #expect(try BlockCoding.decode(
            ProgressPayload.self, from: Data(#"{"style":"holographic"}"#.utf8)
        ).style == .bar)

        #expect(try BlockCoding.decode(
            RatingPayload.self, from: Data(#"{"symbol":"asterisk"}"#.utf8)
        ).symbol == .star)

        #expect(try BlockCoding.decode(
            TimerPayload.self, from: Data(#"{"sound":"foghorn"}"#.utf8)
        ).sound == .chime)

        #expect(try BlockCoding.decode(
            TablePayload.self, from: Data(#"{"columns":[{"title":"A","kind":"hologram"}]}"#.utf8)
        ).columns[0].kind == .text)
    }
}

@Suite("Rest timer")
struct RestTimerTests {

    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func state(duration: TimeInterval = 90) -> RestTimerState {
        RestTimerState(blockID: UUID(), endsAt: start.addingTimeInterval(duration), duration: duration)
    }

    /// Wall-clock, not a tick count: this is the property that makes a timer
    /// survive being suspended.
    @Test("Remaining time is computed from the clock, not counted down")
    func remainingIsWallClock() {
        let timer = state(duration: 90)

        #expect(timer.remaining(at: start) == 90)
        #expect(timer.remaining(at: start.addingTimeInterval(30)) == 60)
        // Whether the app was running for this hour is irrelevant.
        #expect(timer.remaining(at: start.addingTimeInterval(3600)) == 0)
    }

    @Test("A timer finishes once its end passes")
    func finishing() {
        let timer = state(duration: 90)

        #expect(!timer.isFinished(at: start))
        #expect(!timer.isFinished(at: start.addingTimeInterval(89)))
        #expect(timer.isFinished(at: start.addingTimeInterval(90)))
        #expect(timer.isFinished(at: start.addingTimeInterval(10_000)))
    }

    @Test("Elapsed fraction runs 0 to 1 and stops there")
    func fractionElapsed() {
        var timer = state(duration: 100)
        timer.remainingWhenPaused = 100
        #expect(timer.fractionElapsed == 0)

        timer.remainingWhenPaused = 25
        #expect(timer.fractionElapsed == 0.75)

        timer.remainingWhenPaused = 0
        #expect(timer.fractionElapsed == 1)
    }

    @Test("A paused timer holds its remaining time and never finishes")
    func pausedTimerHolds() {
        var timer = state(duration: 90)
        timer.remainingWhenPaused = 45

        #expect(timer.isPaused)
        #expect(timer.remaining(at: start.addingTimeInterval(10_000)) == 45)
        #expect(!timer.isFinished(at: start.addingTimeInterval(10_000)))
    }

    @Test("A zero-duration timer reports a sane fraction rather than dividing by zero")
    func zeroDurationIsSafe() {
        var timer = RestTimerState(blockID: UUID(), endsAt: start, duration: 0)
        timer.remainingWhenPaused = 0
        #expect(timer.fractionElapsed == 0)
    }

    @Test("Running timers survive being encoded for relaunch")
    func stateRoundTrips() throws {
        let timer = state(duration: 90)
        let data = try JSONEncoder().encode([timer])
        let restored = try JSONDecoder().decode([RestTimerState].self, from: data)
        #expect(restored == [timer])
    }
}
