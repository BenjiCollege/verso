import Foundation
import OSLog
import SwiftData
import UserNotifications

/// A schedule block, lifted out of the store so it can be planned off the main
/// actor.
struct ScheduleSnapshot: Sendable {
    var blockID: UUID
    var noteTitle: String
    var payload: SchedulePayload
}

@ModelActor
actor ScheduleSource {
    func snapshots() -> [ScheduleSnapshot] {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { !$0.isTrashed && !$0.isHidden }
        )
        let notes = (try? modelContext.fetch(descriptor)) ?? []

        return notes.flatMap { note in
            note.orderedBlocks
                .filter { $0.type == .schedule }
                .compactMap { block in
                    guard let payload = try? block.decoded(as: SchedulePayload.self), payload.isArmed else {
                        return nil
                    }
                    return ScheduleSnapshot(blockID: block.id, noteTitle: note.title, payload: payload)
                }
        }
    }
}

/// Keeps the system's pending notifications in step with the library's
/// schedule blocks.
///
/// iOS keeps 64 pending local notifications per app and silently drops the
/// rest, so this budgets deliberately and reports what it had to leave out —
/// the same rule the geofence manager follows, for the same reason.
@MainActor
@Observable
final class ScheduleService {

    nonisolated static let logger = Logger(subsystem: "com.verso.notes", category: "schedule")

    private(set) var scheduledCount = 0
    private(set) var droppedCount = 0
    private(set) var isAuthorized = false

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let center: UNUserNotificationCenter

    init(container: ModelContainer, center: UNUserNotificationCenter = .current()) {
        self.container = container
        self.center = center
    }

    var warning: String? {
        guard droppedCount > 0 else { return nil }
        return String(localized: "\(droppedCount) reminders aren't scheduled. iOS holds \(ScheduleNotificationPlanner.systemPendingLimit) pending reminders at once.")
    }

    func requestAuthorization() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])) ?? false
        isAuthorized = granted
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Rebuilds every schedule notification from scratch.
    ///
    /// Cheaper than it sounds — the plan is bounded by the budget — and much
    /// safer than incremental patching, which drifts the moment an edit is
    /// missed and leaves reminders firing for things that no longer exist.
    func refresh(now: Date = Date(), calendar: Calendar = .current) async {
        await refreshAuthorizationStatus()

        let snapshots = await ScheduleSource(modelContainer: container).snapshots()

        let planned = snapshots.flatMap { snapshot in
            ScheduleNotificationPlanner.plan(
                for: snapshot.payload,
                blockID: snapshot.blockID,
                noteTitle: snapshot.noteTitle,
                now: now,
                calendar: calendar
            )
        }

        let (scheduled, dropped) = ScheduleNotificationPlanner.applyBudget(planned)
        scheduledCount = scheduled.count
        droppedCount = dropped.count

        await clearScheduleNotifications()
        guard isAuthorized else { return }

        for notification in scheduled {
            await add(notification, now: now)
        }

        Self.logger.info("Scheduled \(scheduled.count, privacy: .public) reminders, dropped \(dropped.count, privacy: .public).")
    }

    /// Removes everything this block owns. Called when a schedule block is
    /// deleted, so a reminder cannot outlive the thing it was reminding about.
    func cancel(blockID: UUID) async {
        let prefix = ScheduleNotificationPlanner.identifierPrefix(for: blockID)
        let pending = await center.pendingNotificationRequests()
        let doomed = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: doomed)
    }

    // MARK: - Private

    private func clearScheduleNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let doomed = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(ScheduleNotificationPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: doomed)
    }

    private func add(_ notification: PlannedNotification, now: Date) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger: UNNotificationTrigger
        if let components = notification.repeatingComponents {
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        } else {
            let interval = notification.fireAt.timeIntervalSince(now)
            guard interval > 0 else { return }
            // A calendar trigger rather than an interval one, so the reminder
            // lands at the wall-clock time the user chose even if the device
            // changes time zone before then.
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: notification.fireAt
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            Self.logger.error("Reminder rejected: \(error.localizedDescription, privacy: .public)")
        }
    }
}
