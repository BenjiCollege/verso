import Foundation
import Testing
@testable import Verso

@Suite("Recurrence")
struct RecurrenceTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2 // Monday, so week boundaries are predictable.
        return calendar
    }()

    /// Wednesday 9 October 2024, 09:00 UTC.
    private var start: Date {
        calendar.date(from: DateComponents(year: 2024, month: 10, day: 9, hour: 9))!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Frequencies

    @Test("Daily recurrence steps a day at a time")
    func daily() {
        let dates = Recurrence(frequency: .daily).occurrences(
            start: start, after: start, limit: 3, calendar: calendar
        )
        #expect(dates == [date(2024, 10, 10), date(2024, 10, 11), date(2024, 10, 12)])
    }

    @Test("An interval skips periods")
    func interval() {
        let dates = Recurrence(frequency: .daily, interval: 3).occurrences(
            start: start, after: start, limit: 2, calendar: calendar
        )
        #expect(dates == [date(2024, 10, 12), date(2024, 10, 15)])
    }

    @Test("An interval of zero is treated as one rather than looping forever")
    func zeroIntervalIsClamped() {
        #expect(Recurrence(interval: 0).interval == 1)
        #expect(Recurrence(interval: -5).interval == 1)
    }

    @Test("Weekly recurrence keeps the starting weekday")
    func weekly() {
        let dates = Recurrence(frequency: .weekly).occurrences(
            start: start, after: start, limit: 2, calendar: calendar
        )
        #expect(dates == [date(2024, 10, 16), date(2024, 10, 23)])
    }

    @Test("Weekly with several weekdays produces each one, in order")
    func weeklyWithWeekdays() {
        // Monday (2) and Thursday (5), from a Wednesday start.
        let dates = Recurrence(frequency: .weekly, weekdays: [2, 5]).occurrences(
            start: start, after: start, limit: 4, calendar: calendar
        )
        #expect(dates == [
            date(2024, 10, 10), // Thu, same week
            date(2024, 10, 14), // Mon
            date(2024, 10, 17), // Thu
            date(2024, 10, 21), // Mon
        ])
    }

    @Test("Weekdays keep the time of day the series started at")
    func weekdaysKeepTheTime() {
        let dates = Recurrence(frequency: .weekly, weekdays: [5]).occurrences(
            start: start, after: start, limit: 1, calendar: calendar
        )
        #expect(calendar.component(.hour, from: dates[0]) == 9)
    }

    @Test("Out-of-range weekdays are discarded")
    func weekdaysAreValidated() {
        #expect(Recurrence(weekdays: [0, 3, 8, 5]).weekdays == [3, 5])
    }

    @Test("Monthly recurrence steps months")
    func monthly() {
        let dates = Recurrence(frequency: .monthly).occurrences(
            start: start, after: start, limit: 2, calendar: calendar
        )
        #expect(dates == [date(2024, 11, 9), date(2024, 12, 9)])
    }

    /// A monthly reminder set on the 31st has to land somewhere in February.
    @Test("A monthly series starting on the 31st clamps in short months")
    func monthlyClampsShortMonths() {
        let start = date(2024, 1, 31)
        let dates = Recurrence(frequency: .monthly).occurrences(
            start: start, after: start, limit: 2, calendar: calendar
        )
        #expect(dates.count == 2)
        #expect(calendar.component(.month, from: dates[0]) == 2)
        #expect(calendar.component(.day, from: dates[0]) == 29, "2024 is a leap year")
    }

    @Test("Yearly recurrence steps years")
    func yearly() {
        let dates = Recurrence(frequency: .yearly).occurrences(
            start: start, after: start, limit: 2, calendar: calendar
        )
        #expect(dates == [date(2025, 10, 9), date(2026, 10, 9)])
    }

    // MARK: - Limits

    @Test("An end date stops the series")
    func endDateStops() {
        let recurrence = Recurrence(frequency: .daily, endsOn: date(2024, 10, 12))
        let dates = recurrence.occurrences(start: start, after: start, limit: 10, calendar: calendar)
        #expect(dates == [date(2024, 10, 10), date(2024, 10, 11), date(2024, 10, 12)])
    }

    /// The count includes the first occurrence, even though that one is in the
    /// past and never returned — otherwise "five times" quietly means six.
    @Test("An occurrence limit counts from the start of the series")
    func occurrenceLimitCountsTheFirst() {
        let recurrence = Recurrence(frequency: .daily, occurrenceLimit: 3)
        let dates = recurrence.occurrences(start: start, after: start, limit: 10, calendar: calendar)
        #expect(dates == [date(2024, 10, 10), date(2024, 10, 11)])
    }

    @Test("Only occurrences after the cutoff are returned")
    func cutoffIsRespected() {
        let dates = Recurrence(frequency: .daily).occurrences(
            start: start, after: date(2024, 10, 12), limit: 2, calendar: calendar
        )
        #expect(dates == [date(2024, 10, 13), date(2024, 10, 14)])
    }

    @Test("A limit of zero returns nothing")
    func zeroLimit() {
        #expect(Recurrence().occurrences(start: start, after: start, limit: 0, calendar: calendar).isEmpty)
    }

    @Test("A series entirely in the past returns nothing rather than spinning")
    func exhaustedSeriesTerminates() {
        let recurrence = Recurrence(frequency: .daily, endsOn: date(2024, 10, 10))
        let dates = recurrence.occurrences(
            start: start, after: date(2030, 1, 1), limit: 5, calendar: calendar
        )
        #expect(dates.isEmpty)
    }

    // MARK: - System triggers

    /// A repeating trigger is the only kind that still fires for someone who
    /// never opens the app again, so mapping onto one when possible matters.
    @Test("Simple series map onto a repeating system trigger")
    func simpleSeriesAreSystemRepeatable() {
        #expect(Recurrence(frequency: .daily).isSystemRepeatable)
        #expect(Recurrence(frequency: .weekly, weekdays: [3]).isSystemRepeatable)
        #expect(Recurrence(frequency: .monthly).isSystemRepeatable)
    }

    @Test("Anything the system cannot express repeats in software instead")
    func complexSeriesAreNotSystemRepeatable() {
        #expect(!Recurrence(frequency: .daily, interval: 2).isSystemRepeatable)
        #expect(!Recurrence(frequency: .weekly, weekdays: [2, 5]).isSystemRepeatable)
        #expect(!Recurrence(frequency: .daily, endsOn: Date()).isSystemRepeatable)
        #expect(!Recurrence(frequency: .daily, occurrenceLimit: 3).isSystemRepeatable)
    }

    @Test("Trigger components carry the time, and the date parts the frequency needs")
    func triggerComponents() throws {
        let daily = try #require(Recurrence(frequency: .daily).systemTriggerComponents(start: start, calendar: calendar))
        #expect(daily.hour == 9)
        #expect(daily.minute == 0)
        #expect(daily.day == nil)

        let weekly = try #require(
            Recurrence(frequency: .weekly, weekdays: [5]).systemTriggerComponents(start: start, calendar: calendar)
        )
        #expect(weekly.weekday == 5)

        let monthly = try #require(
            Recurrence(frequency: .monthly).systemTriggerComponents(start: start, calendar: calendar)
        )
        #expect(monthly.day == 9)

        let yearly = try #require(
            Recurrence(frequency: .yearly).systemTriggerComponents(start: start, calendar: calendar)
        )
        #expect(yearly.day == 9)
        #expect(yearly.month == 10)

        #expect(Recurrence(frequency: .daily, interval: 2).systemTriggerComponents(start: start, calendar: calendar) == nil)
    }
}

@Suite("Schedule notification planning")
struct ScheduleNotificationPlannerTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let blockID = UUID()

    private func plan(_ payload: SchedulePayload, limit: Int = 8) -> [PlannedNotification] {
        ScheduleNotificationPlanner.plan(
            for: payload,
            blockID: blockID,
            noteTitle: "Groceries",
            now: now,
            limit: limit,
            calendar: calendar
        )
    }

    @Test("Nothing is planned without a due date or an alarm")
    func nothingToPlan() {
        #expect(plan(SchedulePayload(alarms: [.init()])).isEmpty)
        #expect(plan(SchedulePayload(dueAt: now.addingTimeInterval(3600), alarms: [])).isEmpty)
    }

    @Test("A one-off due date produces one notification per alarm")
    func oneOffWithAlarms() {
        let due = now.addingTimeInterval(86_400)
        let planned = plan(SchedulePayload(
            dueAt: due,
            alarms: [.init(offset: 0), .init(offset: -3600)]
        ))

        #expect(planned.count == 2)
        #expect(planned.map(\.fireAt) == [due.addingTimeInterval(-3600), due])
        #expect(planned.allSatisfy { !$0.isRepeating })
    }

    /// A notification in the past is not a reminder, it is an immediate alert
    /// about something that already happened.
    @Test("Alarms that have already passed are dropped")
    func pastAlarmsAreDropped() {
        let due = now.addingTimeInterval(600)
        let planned = plan(SchedulePayload(
            dueAt: due,
            alarms: [.init(offset: 0), .init(offset: -3600), .init(offset: -86_400)]
        ))

        #expect(planned.count == 1)
        #expect(planned[0].fireAt == due)
    }

    @Test("An entirely past schedule plans nothing")
    func pastScheduleIsEmpty() {
        #expect(plan(SchedulePayload(dueAt: now.addingTimeInterval(-86_400), alarms: [.init()])).isEmpty)
    }

    @Test("A simple repeating series becomes one repeating trigger")
    func simpleRecurrenceIsRepeating() throws {
        let planned = plan(SchedulePayload(
            dueAt: now.addingTimeInterval(3600),
            recurrence: Recurrence(frequency: .daily),
            alarms: [.init(offset: 0)]
        ))

        #expect(planned.count == 1)
        let single = try #require(planned.first)
        #expect(single.isRepeating)
        #expect(single.identifier.hasSuffix("repeating"))
    }

    /// A repeating trigger can only fire at the due time, so an early alarm
    /// forces the series to be scheduled as concrete dates instead.
    @Test("An offset alarm forces concrete dates rather than a repeating trigger")
    func offsetAlarmForcesConcreteDates() {
        let planned = plan(SchedulePayload(
            dueAt: now.addingTimeInterval(86_400),
            recurrence: Recurrence(frequency: .daily),
            alarms: [.init(offset: -1800)]
        ))

        #expect(planned.count > 1)
        #expect(planned.allSatisfy { !$0.isRepeating })
    }

    @Test("A complex series is scheduled a few occurrences ahead")
    func complexRecurrenceIsExpanded() {
        let planned = plan(
            SchedulePayload(
                dueAt: now.addingTimeInterval(3600),
                recurrence: Recurrence(frequency: .daily, interval: 2),
                alarms: [.init(offset: 0)]
            ),
            limit: 4
        )

        #expect(planned.count == 4)
        #expect(planned.allSatisfy { !$0.isRepeating })
        #expect(planned.map(\.fireAt) == planned.map(\.fireAt).sorted())
    }

    @Test("Every notification from one block shares its identifier prefix")
    func identifiersAreScopedToTheBlock() {
        let prefix = ScheduleNotificationPlanner.identifierPrefix(for: blockID)
        let planned = plan(SchedulePayload(
            dueAt: now.addingTimeInterval(86_400),
            recurrence: Recurrence(frequency: .daily),
            alarms: [.init(offset: -60), .init(offset: -120)]
        ))

        #expect(!planned.isEmpty)
        #expect(planned.allSatisfy { $0.identifier.hasPrefix(prefix) })
        #expect(Set(planned.map(\.identifier)).count == planned.count, "identifiers must be unique")
    }

    @Test("The block's label wins over the note's title, and the note's over nothing")
    func titleFallsBack() {
        let due = now.addingTimeInterval(3600)
        #expect(plan(SchedulePayload(label: "Collect parcel", dueAt: due, alarms: [.init()]))[0].title == "Collect parcel")
        #expect(plan(SchedulePayload(dueAt: due, alarms: [.init()]))[0].title == "Groceries")
    }

    // MARK: - Budget

    /// iOS keeps 64 pending notifications and silently discards the rest, so
    /// the choice of which 64 has to be made deliberately.
    @Test("Over budget, the soonest survive and the rest are reported")
    func budgetKeepsTheSoonest() {
        let plans = (0..<60).map { index in
            PlannedNotification(
                identifier: "n\(index)",
                fireAt: now.addingTimeInterval(Double(index) * 3600),
                title: "t",
                body: "b"
            )
        }

        let (scheduled, dropped) = ScheduleNotificationPlanner.applyBudget(plans.shuffled(), limit: 10)

        #expect(scheduled.count == 10)
        #expect(dropped.count == 50)
        #expect(scheduled.map(\.fireAt) == plans.prefix(10).map(\.fireAt))
    }

    /// One repeating trigger costs a single slot and covers a series forever,
    /// so it is never the thing that gets dropped.
    @Test("Repeating triggers are kept whatever else goes")
    func repeatingTriggersSurviveTheBudget() {
        let repeating = PlannedNotification(
            identifier: "r",
            fireAt: now.addingTimeInterval(999_999),
            title: "t",
            body: "b",
            repeatingComponents: DateComponents(hour: 9)
        )
        let oneOff = (0..<10).map { index in
            PlannedNotification(
                identifier: "n\(index)",
                fireAt: now.addingTimeInterval(Double(index)),
                title: "t",
                body: "b"
            )
        }

        let (scheduled, dropped) = ScheduleNotificationPlanner.applyBudget(oneOff + [repeating], limit: 3)

        #expect(scheduled.contains(repeating))
        #expect(scheduled.count == 3)
        #expect(dropped.count == 8)
    }

    @Test("Under budget, nothing is dropped")
    func underBudgetKeepsEverything() {
        let plans = [PlannedNotification(identifier: "a", fireAt: now, title: "t", body: "b")]
        let (scheduled, dropped) = ScheduleNotificationPlanner.applyBudget(plans, limit: 10)
        #expect(scheduled.count == 1)
        #expect(dropped.isEmpty)
    }

    @Test("The schedule budget stays under the system's pending limit")
    func budgetLeavesRoomForOtherNotifications() {
        #expect(ScheduleNotificationPlanner.scheduleBudget < ScheduleNotificationPlanner.systemPendingLimit)
    }
}

@Suite("Time and place payloads")
struct TimeAndPlacePayloadTests {

    @Test("Schedule payload survives encode/decode")
    func scheduleRoundTrip() throws {
        let original = SchedulePayload(
            label: "Collect parcel",
            dueAt: Date(timeIntervalSince1970: 1_760_000_000),
            recurrence: Recurrence(frequency: .weekly, interval: 2, weekdays: [2, 5], occurrenceLimit: 6),
            alarms: [.init(offset: 0), .init(offset: -3600)]
        )
        #expect(try BlockCoding.decode(SchedulePayload.self, from: BlockCoding.encode(original)) == original)
    }

    @Test("Place payload survives encode/decode", arguments: PlaceTrigger.allCases)
    func placeRoundTrip(trigger: PlaceTrigger) throws {
        let original = PlacePayload(
            name: "The shop",
            coordinate: Coordinate(latitude: 51.5074, longitude: -0.1278),
            radius: 250,
            trigger: trigger
        )
        #expect(try BlockCoding.decode(PlacePayload.self, from: BlockCoding.encode(original)) == original)
    }

    @Test("A category place round-trips without a coordinate")
    func categoryPlaceRoundTrip() throws {
        let original = PlacePayload(name: "Any grocery store", poiCategory: "MKPOICategoryFoodMarket")
        let restored = try BlockCoding.decode(PlacePayload.self, from: BlockCoding.encode(original))

        #expect(restored == original)
        #expect(restored.target.isCategory)
        #expect(restored.target.isResolvable)
    }

    @Test("A null-island coordinate decodes to no coordinate at all")
    func nullIslandDecodesToNil() throws {
        let data = Data(#"{"name":"x","coordinate":{"latitude":0,"longitude":0}}"#.utf8)
        #expect(try BlockCoding.decode(PlacePayload.self, from: data).coordinate == nil)
    }

    @Test("Unknown triggers and frequencies degrade rather than throw")
    func unknownEnumsDegrade() throws {
        #expect(try BlockCoding.decode(
            PlacePayload.self, from: Data(#"{"trigger":"teleport"}"#.utf8)
        ).trigger == .arrive)

        #expect(try BlockCoding.decode(
            Recurrence.self, from: Data(#"{"frequency":"fortnightly"}"#.utf8)
        ).frequency == .daily)
    }

    @Test("A checklist item's place converts to the same shape a place block uses")
    func checklistItemPlaceBridges() {
        let target = ChecklistPayload.ItemPlace(latitude: 51.5, longitude: -0.12, radius: 300)
            .target(named: "Milk")

        #expect(target.name == "Milk")
        #expect(target.coordinate?.isValid == true)
        #expect(target.radius == 300)
        #expect(target.trigger == .arrive)

        let categoryOnly = ChecklistPayload.ItemPlace(poiCategory: "MKPOICategoryFoodMarket").target(named: "Milk")
        #expect(categoryOnly.coordinate == nil)
        #expect(categoryOnly.isCategory)
    }
}
