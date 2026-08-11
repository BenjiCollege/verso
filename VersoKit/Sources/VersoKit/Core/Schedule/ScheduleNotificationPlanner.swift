import Foundation

/// One notification we intend to schedule.
struct PlannedNotification: Hashable, Sendable, Identifiable {
    var id: String { identifier }
    var identifier: String
    var fireAt: Date
    var title: String
    var body: String
    /// Set when the whole series fits a repeating system trigger, so it keeps
    /// firing for someone who never opens the app again.
    var repeatingComponents: DateComponents?

    var isRepeating: Bool { repeatingComponents != nil }
}

/// Turns a `schedule` block into concrete notification requests.
///
/// Pure. Every date decision — which occurrences, which alarms, what gets
/// dropped for being in the past — happens here rather than inside a call to
/// `UNUserNotificationCenter`, so all of it is testable.
enum ScheduleNotificationPlanner {

    static let identifierPrefix = "verso.schedule."

    /// iOS keeps at most 64 pending local notifications per app and silently
    /// discards the rest. Verso budgets below that so a rest timer and a place
    /// reminder can still get one.
    static let systemPendingLimit = 64
    static let scheduleBudget = 48

    /// How many future occurrences of one block to schedule ahead. Topped up
    /// whenever the app runs.
    static let occurrencesPerBlock = 8

    static func identifierPrefix(for blockID: UUID) -> String {
        identifierPrefix + blockID.uuidString + "."
    }

    static func plan(
        for payload: SchedulePayload,
        blockID: UUID,
        noteTitle: String,
        now: Date = Date(),
        limit: Int = occurrencesPerBlock,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        guard let dueAt = payload.dueAt, !payload.alarms.isEmpty else { return [] }

        let title = payload.label.isEmpty
            ? (noteTitle.isEmpty ? String(localized: "Reminder") : noteTitle)
            : payload.label

        // A repeating series that the system can express natively is scheduled
        // once, as one repeating trigger, rather than as a handful of dates
        // that run out.
        if let recurrence = payload.recurrence,
           let components = recurrence.systemTriggerComponents(start: dueAt, calendar: calendar),
           payload.alarms.count == 1,
           payload.alarms[0].offset == 0 {
            return [
                PlannedNotification(
                    identifier: identifierPrefix(for: blockID) + "repeating",
                    fireAt: dueAt,
                    title: title,
                    body: body(for: payload, occurrence: dueAt, alarm: payload.alarms[0]),
                    repeatingComponents: components
                )
            ]
        }

        let occurrences: [Date]
        if let recurrence = payload.recurrence {
            // `after: now - 1 day` so a due time earlier today still produces
            // its alarms, which may themselves be in the future.
            var dates = recurrence.occurrences(
                start: dueAt,
                after: now.addingTimeInterval(-86_400),
                limit: limit,
                calendar: calendar
            )
            if dueAt > now, !dates.contains(dueAt) { dates.insert(dueAt, at: 0) }
            occurrences = Array(dates.prefix(limit))
        } else {
            occurrences = [dueAt]
        }

        var planned: [PlannedNotification] = []
        for (occurrenceIndex, occurrence) in occurrences.enumerated() {
            for alarm in payload.alarms {
                let fireAt = occurrence.addingTimeInterval(alarm.offset)
                // A notification in the past is not a reminder, it is an
                // immediate alert about something that already happened.
                guard fireAt > now else { continue }

                planned.append(
                    PlannedNotification(
                        identifier: "\(identifierPrefix(for: blockID))\(occurrenceIndex).\(alarm.id.uuidString)",
                        fireAt: fireAt,
                        title: title,
                        body: body(for: payload, occurrence: occurrence, alarm: alarm),
                        repeatingComponents: nil
                    )
                )
            }
        }

        return planned.sorted { $0.fireAt < $1.fireAt }
    }

    private static func body(for payload: SchedulePayload, occurrence: Date, alarm: SchedulePayload.Alarm) -> String {
        let when = occurrence.formatted(date: .abbreviated, time: .shortened)
        return alarm.offset == 0
            ? String(localized: "Due now — \(when)")
            : String(localized: "Due \(when)")
    }

    /// Trims a whole library's worth of plans to the app's budget, taking the
    /// soonest first so that what survives is what matters next.
    ///
    /// Returns the dropped ones as well: something the user asked for is not
    /// going to happen, and they need to be able to find out why.
    static func applyBudget(
        _ plans: [PlannedNotification],
        limit: Int = scheduleBudget
    ) -> (scheduled: [PlannedNotification], dropped: [PlannedNotification]) {
        // Repeating triggers are kept whatever else goes: each one costs a
        // single slot and covers a series indefinitely.
        let repeating = plans.filter(\.isRepeating)
        let oneOff = plans.filter { !$0.isRepeating }.sorted { $0.fireAt < $1.fireAt }

        let remaining = max(0, limit - repeating.count)
        return (
            scheduled: repeating + Array(oneOff.prefix(remaining)),
            dropped: Array(oneOff.dropFirst(remaining))
        )
    }
}
