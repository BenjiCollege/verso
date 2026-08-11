import Foundation
import SwiftData
import Testing
@testable import VersoKit

@Suite("Metric series")
struct MetricSeriesTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let start = calendar.startOfDay(for: base)
        return calendar.date(byAdding: .day, value: offset, to: start)!
            .addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func makeStore() throws -> (MetricSeriesStore, ModelContext) {
        let context = ModelContext(try VersoModelContainer.makeInMemory())
        return (MetricSeriesStore(context: context), context)
    }

    // MARK: - Aggregation

    @Test("Readings on the same day fold into one point")
    func dailyBucketing() {
        let readings = [
            (date: day(0, hour: 8), value: 250.0),
            (date: day(0, hour: 14), value: 500.0),
            (date: day(1, hour: 9), value: 750.0),
        ]

        let points = MetricAggregator.daily(readings, using: .sum, calendar: calendar)

        #expect(points.count == 2)
        #expect(points[0].value == 750)
        #expect(points[0].count == 2)
        #expect(points[1].value == 750)
        #expect(points[1].count == 1)
        #expect(points[0].date < points[1].date)
    }

    @Test("Every aggregation folds the same day differently", arguments: [
        (MetricAggregation.sum, 12.0),
        (.average, 4.0),
        (.maximum, 6.0),
        (.minimum, 2.0),
        (.latest, 6.0),
    ])
    func aggregations(aggregation: MetricAggregation, expected: Double) {
        let readings = [
            (date: day(0, hour: 8), value: 4.0),
            (date: day(0, hour: 9), value: 2.0),
            (date: day(0, hour: 10), value: 6.0),
        ]
        let points = MetricAggregator.daily(readings, using: aggregation, calendar: calendar)
        #expect(points.count == 1)
        #expect(points[0].value == expected)
    }

    @Test("Points come back in date order however they went in")
    func pointsAreSorted() {
        let readings = [
            (date: day(3), value: 3.0),
            (date: day(1), value: 1.0),
            (date: day(2), value: 2.0),
        ]
        let points = MetricAggregator.daily(readings, using: .sum, calendar: calendar)
        #expect(points.map(\.value) == [1, 2, 3])
    }

    @Test("No readings, no points")
    func emptyAggregation() {
        // Spelled out because `daily` is overloaded on readings and on
        // `MetricEntry`, and an empty literal matches both.
        let none: [(date: Date, value: Double)] = []
        #expect(MetricAggregator.daily(none, using: .sum, calendar: calendar).isEmpty)
    }

    /// A trend line drawn from fewer points than its own window is a line
    /// through noise.
    @Test("A moving average needs a full window before it draws anything")
    func movingAverageNeedsAFullWindow() {
        let points = (0..<5).map { MetricPoint(date: day($0), value: Double($0 + 1), count: 1) }

        #expect(MetricAggregator.movingAverage(points, window: 7).isEmpty)
        #expect(MetricAggregator.movingAverage(points, window: 1).isEmpty)

        let averaged = MetricAggregator.movingAverage(points, window: 3)
        #expect(averaged.map(\.value) == [2, 3, 4])
        // Each point is stamped at the end of its window, not the middle.
        #expect(averaged[0].date == points[2].date)
    }

    // MARK: - Store

    @Test("A series query returns only its own readings, in order")
    func seriesQueryIsScoped() throws {
        let (store, context) = try makeStore()
        let noteID = UUID()

        context.insert(MetricEntry(seriesID: "bench-press", label: "Bench", value: 80, unit: "kg", recordedAt: day(1), noteID: noteID))
        context.insert(MetricEntry(seriesID: "bench-press", label: "Bench", value: 85, unit: "kg", recordedAt: day(3), noteID: noteID))
        context.insert(MetricEntry(seriesID: "water", label: "Water", value: 500, unit: "ml", recordedAt: day(2), noteID: noteID))
        try context.save()

        #expect(store.values(seriesID: "bench-press") == [80, 85])
        #expect(store.values(seriesID: "water") == [500])
        #expect(store.values(seriesID: "nothing").isEmpty)
    }

    @Test("A window excludes readings older than itself")
    func windowFiltersByDate() throws {
        let (store, context) = try makeStore()
        let now = day(100)

        context.insert(MetricEntry(seriesID: "weight", value: 70, recordedAt: day(0), noteID: UUID()))
        context.insert(MetricEntry(seriesID: "weight", value: 71, recordedAt: day(97), noteID: UUID()))
        try context.save()

        #expect(store.values(seriesID: "weight", in: .week, now: now) == [71])
        #expect(store.values(seriesID: "weight", in: .all, now: now) == [70, 71])
    }

    /// The point of keying on `(noteID, seriesID, groupID)`: editing a number
    /// corrects the reading instead of logging a second one.
    @Test("Recording twice for the same block updates rather than duplicates")
    func recordingIsIdempotent() throws {
        let (store, context) = try makeStore()
        let noteID = UUID()

        store.record(seriesID: "bench-press", groupID: "set-1", label: "Bench", value: 80, unit: "kg", noteID: noteID)
        store.record(seriesID: "bench-press", groupID: "set-1", label: "Bench", value: 82.5, unit: "kg", noteID: noteID)
        try context.save()

        #expect(store.values(seriesID: "bench-press") == [82.5])
    }

    @Test("Different groups in one note are different readings")
    func groupsAreDistinct() throws {
        let (store, context) = try makeStore()
        let noteID = UUID()

        store.record(seriesID: "bench-press", groupID: "set-1", label: "Bench", value: 80, unit: "kg", noteID: noteID)
        store.record(seriesID: "bench-press", groupID: "set-2", label: "Bench", value: 80, unit: "kg", noteID: noteID)
        try context.save()

        #expect(store.values(seriesID: "bench-press").count == 2)
    }

    @Test("The same series in two notes keeps both readings")
    func notesAreDistinct() throws {
        let (store, context) = try makeStore()

        store.record(seriesID: "weight", groupID: nil, label: "Weight", value: 70, unit: "kg", noteID: UUID())
        store.record(seriesID: "weight", groupID: nil, label: "Weight", value: 71, unit: "kg", noteID: UUID())
        try context.save()

        #expect(store.values(seriesID: "weight").count == 2)
    }

    /// A blank field is not a measurement of zero, and must not pull a chart
    /// down to the axis.
    @Test("Clearing a value deletes the reading rather than storing zero")
    func clearingRemovesTheReading() throws {
        let (store, context) = try makeStore()
        let noteID = UUID()

        store.record(seriesID: "weight", groupID: nil, label: "Weight", value: 70, unit: "kg", noteID: noteID)
        try context.save()
        #expect(store.values(seriesID: "weight") == [70])

        store.record(seriesID: "weight", groupID: nil, label: "Weight", value: nil, unit: "kg", noteID: noteID)
        try context.save()
        #expect(store.values(seriesID: "weight").isEmpty)
    }

    // MARK: - Personal records

    @Test("A personal best is the largest reading in the series")
    func personalBest() throws {
        let (store, context) = try makeStore()
        let noteID = UUID()

        for value in [80.0, 92.5, 85.0] {
            context.insert(MetricEntry(seriesID: "bench-press", value: value, recordedAt: day(Int(value)), noteID: noteID))
        }
        try context.save()

        #expect(store.personalBest(seriesID: "bench-press")?.value == 92.5)
        #expect(store.isPersonalBest(95, seriesID: "bench-press"))
        #expect(!store.isPersonalBest(92.5, seriesID: "bench-press"))
        #expect(!store.isPersonalBest(90, seriesID: "bench-press"))
    }

    /// Without excluding the block's own row, correcting a record downward
    /// would still report itself as a record.
    @Test("A reading does not count itself when checking for a record")
    func personalBestExcludesItself() throws {
        let (store, context) = try makeStore()
        let noteID = UUID()

        let entry = try #require(store.record(
            seriesID: "bench-press", groupID: "set-1", label: "Bench", value: 100, unit: "kg", noteID: noteID
        ))
        context.insert(MetricEntry(seriesID: "bench-press", value: 95, recordedAt: day(0), noteID: noteID))
        try context.save()

        #expect(store.isPersonalBest(100, seriesID: "bench-press", excluding: entry.id))
        #expect(!store.isPersonalBest(90, seriesID: "bench-press", excluding: entry.id))
    }

    @Test("The first reading in a series is a record")
    func firstReadingIsARecord() throws {
        let (store, _) = try makeStore()
        #expect(store.isPersonalBest(1, seriesID: "brand-new"))
        #expect(store.personalBest(seriesID: "brand-new") == nil)
    }

    @Test("Known series are listed most recently used first")
    func knownSeries() throws {
        let (store, context) = try makeStore()

        context.insert(MetricEntry(seriesID: "old", value: 1, recordedAt: day(0), noteID: UUID()))
        context.insert(MetricEntry(seriesID: "new", value: 1, recordedAt: day(5), noteID: UUID()))
        context.insert(MetricEntry(seriesID: "new", value: 2, recordedAt: day(6), noteID: UUID()))
        try context.save()

        #expect(store.knownSeriesIDs() == ["new", "old"])
    }

    // MARK: - Slugging

    @Test("Labels slug to stable series ids", arguments: [
        ("Bench Press", "bench-press"),
        ("  Bench   Press  ", "bench-press"),
        ("BENCH PRESS", "bench-press"),
        ("Front Squat (3RM)", "front-squat-3rm"),
        ("Café au lait", "cafe-au-lait"),
        ("", ""),
    ])
    func slugging(label: String, expected: String) {
        #expect(MetricPayload.slug(label) == expected)
    }

    @Test("A metric with no declared series derives one from its label")
    func seriesDerivedFromLabel() throws {
        let data = Data(#"{"label":"Bench Press","unit":"kg"}"#.utf8)
        let payload = try BlockCoding.decode(MetricPayload.self, from: data)
        #expect(payload.seriesID == "bench-press")
    }

    @Test("A declared series wins over the label")
    func declaredSeriesWins() throws {
        let data = Data(#"{"label":"Bench Press","seriesID":"bp-competition"}"#.utf8)
        let payload = try BlockCoding.decode(MetricPayload.self, from: data)
        #expect(payload.seriesID == "bp-competition")
    }
}
