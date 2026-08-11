import Foundation
import SwiftData

/// One point on a chart. A plain `Sendable` value, so the aggregation that
/// produces it is testable without a store, a view, or a chart.
struct MetricPoint: Identifiable, Hashable, Sendable {
    var id: Date { date }
    var date: Date
    var value: Double
    /// How many readings were folded into this point. Shown in the accessibility
    /// description so "82.5 kg" doesn't hide that it was six sets.
    var count: Int
}

/// How several readings on one day become one point.
enum MetricAggregation: String, CaseIterable, Sendable {
    case sum
    case average
    case maximum
    case minimum
    case latest

    var displayName: LocalizedStringResource {
        switch self {
        case .sum: "Total"
        case .average: "Average"
        case .maximum: "Best"
        case .minimum: "Lowest"
        case .latest: "Latest"
        }
    }

    func reduce(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return switch self {
        case .sum: values.reduce(0, +)
        case .average: values.reduce(0, +) / Double(values.count)
        case .maximum: values.max() ?? 0
        case .minimum: values.min() ?? 0
        case .latest: values.last ?? 0
        }
    }
}

enum MetricWindow: String, CaseIterable, Sendable {
    case week
    case month
    case quarter
    case year
    case all

    var displayName: LocalizedStringResource {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .year: "1 year"
        case .all: "All"
        }
    }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .all: nil
        }
    }

    func start(from now: Date, calendar: Calendar = .current) -> Date? {
        guard let days else { return nil }
        return calendar.date(byAdding: .day, value: -days, to: now)
    }
}

/// Reading and aggregating `MetricEntry`.
///
/// Every number in the app lands in the same table under a `seriesID`, so this
/// one type serves bench press, water intake and bodyweight without knowing
/// which is which.
///
/// Deliberately not `@MainActor`: it is a thin wrapper over whichever
/// `ModelContext` it was handed, and it inherits its caller's isolation. Pinning
/// it to the main actor would force every closure that captures it — including
/// a formula's `series(…)` resolver — to become main-actor-isolated too.
struct MetricSeriesStore {

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Fetching

    func entries(seriesID: String, since: Date? = nil) -> [MetricEntry] {
        let descriptor = FetchDescriptor<MetricEntry>(
            predicate: #Predicate<MetricEntry> { $0.seriesID == seriesID },
            sortBy: [SortDescriptor(\MetricEntry.recordedAt)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        guard let since else { return all }
        return all.filter { $0.recordedAt >= since }
    }

    func entries(seriesID: String, in window: MetricWindow, now: Date = Date()) -> [MetricEntry] {
        entries(seriesID: seriesID, since: window.start(from: now))
    }

    func values(seriesID: String, in window: MetricWindow = .all, now: Date = Date()) -> [Double] {
        entries(seriesID: seriesID, in: window, now: now).map(\.value)
    }

    /// Every series that has at least one reading, most recently used first.
    func knownSeriesIDs() -> [String] {
        let descriptor = FetchDescriptor<MetricEntry>(
            sortBy: [SortDescriptor(\MetricEntry.recordedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        var seen = Set<String>()
        return all.map(\.seriesID).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Writing

    /// Records or updates the reading a metric block owns.
    ///
    /// The block's `(noteID, seriesID, groupID)` identifies its row, so editing
    /// a number corrects the reading instead of appending a second one. That is
    /// the difference between a chart of your bench press and a chart of how
    /// many times you tapped the field.
    @discardableResult
    func record(
        seriesID: String,
        groupID: String?,
        label: String,
        value: Double?,
        unit: String,
        noteID: UUID,
        at date: Date = Date()
    ) -> MetricEntry? {
        let existing = findEntry(seriesID: seriesID, groupID: groupID, noteID: noteID)

        guard let value else {
            // Clearing the field removes the reading. A blank metric is not a
            // measurement of zero and must not pull a chart down.
            if let existing { context.delete(existing) }
            return nil
        }

        if let existing {
            existing.value = value
            existing.label = label
            existing.unit = unit
            return existing
        }

        let entry = MetricEntry(
            seriesID: seriesID,
            groupID: groupID,
            label: label,
            value: value,
            unit: unit,
            recordedAt: date,
            noteID: noteID
        )
        context.insert(entry)
        return entry
    }

    func findEntry(seriesID: String, groupID: String?, noteID: UUID) -> MetricEntry? {
        let descriptor = FetchDescriptor<MetricEntry>(
            predicate: #Predicate<MetricEntry> { $0.seriesID == seriesID && $0.noteID == noteID }
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.first { $0.groupID == groupID }
    }

    // MARK: - Personal records

    /// The best reading in a series, and whether a given value beats it.
    ///
    /// "Best" means largest here. A series where lower is better — a mile time,
    /// a resting heart rate — needs its own direction, which arrives with the
    /// templates that have an opinion about it in Phase 5.
    func personalBest(seriesID: String) -> MetricEntry? {
        entries(seriesID: seriesID).max { $0.value < $1.value }
    }

    func isPersonalBest(_ value: Double, seriesID: String, excluding entryID: UUID? = nil) -> Bool {
        let others = entries(seriesID: seriesID).filter { $0.id != entryID }
        guard let best = others.map(\.value).max() else { return true }
        return value > best
    }
}

// MARK: - Aggregation

enum MetricAggregator {

    /// Folds readings into one point per calendar day.
    ///
    /// Pure, and separate from the store, so the bucketing logic — which is
    /// where off-by-one-day bugs live — is testable without SwiftData.
    static func daily(
        _ readings: [(date: Date, value: Double)],
        using aggregation: MetricAggregation,
        calendar: Calendar = .current
    ) -> [MetricPoint] {
        let grouped = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { day, entries in
                let ordered = entries.sorted { $0.date < $1.date }.map(\.value)
                return MetricPoint(date: day, value: aggregation.reduce(ordered), count: ordered.count)
            }
            .sorted { $0.date < $1.date }
    }

    static func daily(
        _ entries: [MetricEntry],
        using aggregation: MetricAggregation,
        calendar: Calendar = .current
    ) -> [MetricPoint] {
        daily(entries.map { (date: $0.recordedAt, value: $0.value) }, using: aggregation, calendar: calendar)
    }

    /// A trailing mean, for the line drawn over the bars. Returns an empty
    /// array rather than a ragged one when there are fewer points than the
    /// window, so a chart never shows a trend it cannot support.
    static func movingAverage(_ points: [MetricPoint], window: Int) -> [MetricPoint] {
        guard window > 1, points.count >= window else { return [] }
        return (0...(points.count - window)).map { start in
            let mean = points[start..<(start + window)].map(\.value).reduce(0, +) / Double(window)
            return MetricPoint(date: points[start + window - 1].date, value: mean, count: window)
        }
    }
}
