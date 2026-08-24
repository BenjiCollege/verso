import ActivityKit
import Foundation
import OSLog

/// Puts a running timer on the Lock Screen, and takes it away again.
///
/// Every method is best-effort and silent on failure. Live Activities can be
/// switched off system-wide, refused per-app, or budget-limited, and none of
/// those is a state the timer should care about — the countdown is
/// authoritative in `RestTimerService` and this is only a window onto it. A
/// timer that failed to start because a Lock Screen widget could not be shown
/// would be an absurd way to lose someone's rest period.
///
/// **Nothing here holds an `Activity`.** That is deliberate, and it is what
/// makes the file compile under strict concurrency: `Activity` is a plain
/// non-`Sendable` class whose methods are nonisolated, so storing one on the
/// main actor and later awaiting a method on it means sending it across an
/// isolation boundary — a real race, and Swift 6 is right to refuse it.
/// Instead each operation looks the activity up from
/// `Activity.activities` inside the same nonisolated context that then uses it,
/// so it never crosses anything. The system's list is the source of truth
/// regardless, which also means a crash cannot leave this out of step with it.
enum TimerLiveActivity {

    private static var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// How long after zero an abandoned activity should be considered stale.
    private static let staleGrace: TimeInterval = 60 * 5

    // MARK: - Control

    static func start(_ state: RestTimerState, label: String) {
        guard isAvailable else { return }
        let attributes = TimerActivityAttributes(
            blockID: state.blockID,
            label: label,
            duration: state.duration
        )
        let content = content(for: state)
        Task { await request(attributes, content) }
    }

    /// Pushes a new end date — used on pause and resume, the only two moments
    /// the countdown's shape actually changes. The seconds in between are drawn
    /// by the system from `endsAt`, not pushed from here.
    static func update(_ state: RestTimerState) {
        let id = state.blockID
        let content = content(for: state)
        Task { await apply(content, to: id) }
    }

    /// Stopped by hand: off the Lock Screen at once, because it is showing a
    /// countdown for something that is no longer counting.
    static func end(blockID: UUID) {
        Task { await dismiss(blockID, policy: .immediate) }
    }

    /// Reached zero on its own: allowed to linger, so a timer that finished
    /// while the phone sat on a table is still readable when it is picked up.
    static func finish(blockID: UUID) {
        Task { await dismiss(blockID, policy: .default) }
    }

    /// Clears activities this process no longer has a timer for.
    ///
    /// A crash mid-timer leaves one running with no `RestTimerState` behind it;
    /// it would otherwise sit there counting down to nothing until the system
    /// reaped it hours later.
    static func endOrphans(keeping ids: Set<UUID>) {
        Task { await endEverythingExcept(ids) }
    }

    // MARK: - Work
    //
    // Each of these is nonisolated and async, and every `Activity` it touches
    // is fetched and used inside the same call. Nothing is stored, nothing is
    // captured, nothing is sent.

    private static func request(
        _ attributes: TimerActivityAttributes,
        _ content: ActivityContent<TimerActivityAttributes.ContentState>
    ) async {
        // Already showing — a re-entrant start would stack two identical
        // activities for one timer.
        guard activity(for: attributes.blockID) == nil else { return }
        do {
            _ = try Activity.request(attributes: attributes, content: content)
        } catch {
            RestTimerService.logger.debug("Live Activity refused: \(error.localizedDescription)")
        }
    }

    private static func apply(
        _ content: ActivityContent<TimerActivityAttributes.ContentState>,
        to blockID: UUID
    ) async {
        guard let activity = activity(for: blockID) else { return }
        await activity.update(content)
    }

    private static func dismiss(_ blockID: UUID, policy: ActivityUIDismissalPolicy) async {
        guard let activity = activity(for: blockID) else { return }
        await activity.end(nil, dismissalPolicy: policy)
    }

    private static func endEverythingExcept(_ ids: Set<UUID>) async {
        for activity in Activity<TimerActivityAttributes>.activities
        where !ids.contains(activity.attributes.blockID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func activity(for blockID: UUID) -> Activity<TimerActivityAttributes>? {
        Activity<TimerActivityAttributes>.activities.first { $0.attributes.blockID == blockID }
    }

    private static func content(
        for state: RestTimerState
    ) -> ActivityContent<TimerActivityAttributes.ContentState> {
        ActivityContent(
            state: TimerActivityAttributes.ContentState(
                endsAt: state.endsAt,
                remainingWhenPaused: state.remainingWhenPaused
            ),
            staleDate: state.endsAt.addingTimeInterval(staleGrace)
        )
    }
}
