import Foundation

/// How often something comes back.
///
/// Kept structured rather than as an RRULE string, because the app has to
/// *compute* occurrences — `UNCalendarNotificationTrigger` can only repeat the
/// simple shapes, and everything else has to be scheduled a few at a time and
/// topped up. Parsing RRULE to do that would be a lot of surface for no gain.
struct Recurrence: Codable, Hashable, Sendable {

    enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily
        case weekly
        case monthly
        case yearly

        var displayName: LocalizedStringResource {
            switch self {
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            case .yearly: "Yearly"
            }
        }

        var component: Calendar.Component {
            switch self {
            case .daily: .day
            case .weekly: .weekOfYear
            case .monthly: .month
            case .yearly: .year
            }
        }
    }

    var frequency: Frequency
    /// Every N periods. Clamped to at least 1, because an interval of zero is
    /// an infinite loop wearing a data model.
    var interval: Int
    /// `Calendar` weekday numbers, 1 = Sunday. Weekly only; empty means "the
    /// same weekday the series started on".
    var weekdays: [Int]
    var endsOn: Date?
    /// Stops after this many occurrences, counting the first.
    var occurrenceLimit: Int?

    init(
        frequency: Frequency = .daily,
        interval: Int = 1,
        weekdays: [Int] = [],
        endsOn: Date? = nil,
        occurrenceLimit: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays.filter { (1...7).contains($0) }.sorted()
        self.endsOn = endsOn
        self.occurrenceLimit = occurrenceLimit.map { max(1, $0) }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawFrequency = try container.decodeIfPresent(String.self, forKey: .frequency) ?? Frequency.daily.rawValue
        self.init(
            frequency: Frequency(rawValue: rawFrequency) ?? .daily,
            interval: try container.decodeIfPresent(Int.self, forKey: .interval) ?? 1,
            weekdays: try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? [],
            endsOn: try container.decodeIfPresent(Date.self, forKey: .endsOn),
            occurrenceLimit: try container.decodeIfPresent(Int.self, forKey: .occurrenceLimit)
        )
    }

    /// True when the whole series maps onto a single repeating
    /// `UNCalendarNotificationTrigger`, which is the only way a reminder still
    /// fires for someone who never opens the app again.
    var isSystemRepeatable: Bool {
        interval == 1 && weekdays.count <= 1 && endsOn == nil && occurrenceLimit == nil
    }

    var displayDescription: String {
        let every = interval == 1
            ? String(localized: "Every")
            : String(localized: "Every \(interval)")

        return switch frequency {
        case .daily: interval == 1 ? String(localized: "Every day") : "\(every) days"
        case .weekly: interval == 1 ? String(localized: "Every week") : "\(every) weeks"
        case .monthly: interval == 1 ? String(localized: "Every month") : "\(every) months"
        case .yearly: interval == 1 ? String(localized: "Every year") : "\(every) years"
        }
    }
}

// MARK: - Occurrences

extension Recurrence {

    /// Guards against a calendar that refuses to advance — a malformed
    /// recurrence must not spin forever looking for a date that never arrives.
    private static let maximumSteps = 512

    /// The next occurrences of a series that began at `start`.
    ///
    /// - Parameters:
    ///   - start: the first occurrence, whether or not it is in the past.
    ///   - after: only occurrences strictly later than this are returned.
    ///   - limit: how many to produce.
    func occurrences(
        start: Date,
        after: Date,
        limit: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard limit > 0 else { return [] }

        var results: [Date] = []
        var produced = 0
        var step = 0

        while results.count < limit, step < Self.maximumSteps {
            let batch = dates(atStep: step, from: start, calendar: calendar)
            step += 1

            guard !batch.isEmpty else { continue }
            // A step that lands entirely past the end date means every later
            // step will too.
            if let endsOn, batch.allSatisfy({ $0 > endsOn }) { break }

            for date in batch {
                if let endsOn, date > endsOn { continue }
                produced += 1
                if let occurrenceLimit, produced > occurrenceLimit { return results }
                if date > after { results.append(date) }
                if results.count == limit { return results }
            }
        }
        return results
    }

    /// The occurrence(s) produced by one step of the series. Weekly recurrences
    /// with several weekdays produce more than one per step, which is why this
    /// returns an array.
    private func dates(atStep step: Int, from start: Date, calendar: Calendar) -> [Date] {
        let offset = step * interval

        guard frequency == .weekly, !weekdays.isEmpty else {
            guard let date = calendar.date(byAdding: frequency.component, value: offset, to: start) else {
                return []
            }
            return [date]
        }

        guard let weekAnchor = calendar.date(byAdding: .weekOfYear, value: offset, to: start),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)?.start
        else { return [] }

        let timeOfDay = calendar.dateComponents([.hour, .minute, .second], from: start)

        return weekdays.compactMap { weekday in
            // `nextDate` from just before the week's start finds that week's
            // instance of the weekday, rather than one in a neighbouring week.
            var components = DateComponents()
            components.weekday = weekday
            components.hour = timeOfDay.hour
            components.minute = timeOfDay.minute
            components.second = timeOfDay.second

            return calendar.nextDate(
                after: weekStart.addingTimeInterval(-1),
                matching: components,
                matchingPolicy: .nextTime
            )
        }
        .sorted()
    }

    /// The `DateComponents` for a repeating system trigger, when the series is
    /// simple enough to be one. `nil` otherwise.
    func systemTriggerComponents(start: Date, calendar: Calendar = .current) -> DateComponents? {
        guard isSystemRepeatable else { return nil }
        let time = calendar.dateComponents([.hour, .minute], from: start)

        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute

        switch frequency {
        case .daily:
            break
        case .weekly:
            components.weekday = weekdays.first ?? calendar.component(.weekday, from: start)
        case .monthly:
            components.day = calendar.component(.day, from: start)
        case .yearly:
            components.day = calendar.component(.day, from: start)
            components.month = calendar.component(.month, from: start)
        }
        return components
    }
}
