import ActivityKit
import Foundation

/// What a running timer looks like from outside the app.
///
/// A rest timer that vanishes the moment you leave the page is half a feature:
/// the whole reason to set one is that you are about to do something else. This
/// is the shape of that timer on the Lock Screen and in the Dynamic Island.
///
/// Lives in `VersoKit` rather than in either target because both need it — the
/// app to start and update the activity, the widget extension to draw it — and
/// an `ActivityAttributes` type that does not match on both sides fails at
/// runtime with no diagnostic worth reading.
struct TimerActivityAttributes: ActivityAttributes {

    /// The part that changes while the timer runs.
    ///
    /// Deliberately tiny, and deliberately *not* a remaining-seconds count.
    /// ActivityKit budgets updates tightly, so pushing a new number every
    /// second would be throttled into a clock that visibly stutters. `endsAt`
    /// is pushed once and the system counts down from it locally — which is
    /// also why the display stays right while the phone is asleep.
    struct ContentState: Codable, Hashable, Sendable {
        var endsAt: Date
        /// Set while paused, so the Island can show a held figure rather than a
        /// countdown that is silently wrong.
        var remainingWhenPaused: TimeInterval?

        var isPaused: Bool { remainingWhenPaused != nil }
    }

    /// Which timer this is. Matches `RestTimerState.blockID`.
    var blockID: UUID
    /// What the user called it, empty if they called it nothing.
    var label: String
    var duration: TimeInterval

    /// What to call it on a Lock Screen, where "Timer" alone is not much help
    /// if two are running.
    var displayName: String {
        label.isEmpty ? String(localized: "Timer") : label
    }
}
