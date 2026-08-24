import ActivityKit
import SwiftUI
import WidgetKit

/// A running timer, outside the app.
///
/// The countdown is drawn with `Text(timerInterval:)` rather than a number this
/// code updates. That is the whole trick: the system runs the clock locally, so
/// it stays correct while the device is asleep and costs no activity-update
/// budget. Pushing a fresh remaining-seconds value every second would be
/// throttled into a clock that visibly stutters.
public struct TimerLiveActivityWidget: Widget {

    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenTimer(context: context)
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPaused ? "pause.circle" : "timer")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context, font: .title2.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.displayName)
                        .font(.headline)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .accessibilityHidden(true)
            } compactTrailing: {
                countdown(context, font: .caption.monospacedDigit())
                    // Without this the compact region sizes itself to the
                    // widest time the countdown could ever reach and the pill
                    // jitters as digits drop.
                    .frame(width: 44)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .accessibilityHidden(true)
            }
            .widgetURL(URL(string: "verso://timer/\(context.attributes.blockID.uuidString)"))
        }
    }

    /// The time itself, in whichever of its two states it is in.
    ///
    /// A paused timer shows a held figure rather than a live countdown: leaving
    /// `timerInterval` running while paused would show a number ticking down
    /// that the app is not actually counting.
    @ViewBuilder
    private func countdown(
        _ context: ActivityViewContext<TimerActivityAttributes>,
        font: Font
    ) -> some View {
        if let held = context.state.remainingWhenPaused {
            Text(Duration.seconds(max(0, held)), format: .time(pattern: .minuteSecond))
                .font(font)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Paused"))
        } else {
            Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                .font(font)
                .monospacedDigit()
        }
    }
}

/// The Lock Screen presentation — the one most people will actually see.
private struct LockScreenTimer: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        HStack(spacing: Layout.Space.regular) {
            Image(systemName: context.state.isPaused ? "pause.circle.fill" : "timer")
                .font(.title)
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Layout.Space.hair) {
                Text(context.attributes.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(context.state.isPaused ? "Paused" : "Counting down")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: Layout.Space.snug)

            Group {
                if let held = context.state.remainingWhenPaused {
                    Text(Duration.seconds(max(0, held)), format: .time(pattern: .minuteSecond))
                } else {
                    Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                }
            }
            .font(.system(.title, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
        }
        .padding(Layout.Space.regular)
        // One element, so VoiceOver reads "Rest, paused, 1 minute 30 seconds"
        // instead of walking three fragments.
        .accessibilityElement(children: .combine)
    }
}
