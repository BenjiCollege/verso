import SwiftUI

struct TimerBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion
    @Environment(RestTimerService.self) private var timers

    @State private var isEditingDuration = false

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<TimerPayload>) in
            let state = timers.state(for: block.id)
            let hasFinished = timers.justFinished.contains(block.id)

            HStack(spacing: Layout.Space.cosy) {
                dial(state: state, hasFinished: hasFinished, payload: payload.wrappedValue)

                VStack(alignment: .leading, spacing: Layout.Space.hair) {
                    TextField(
                        "Label",
                        text: payload.label,
                        prompt: Text("Timer").foregroundStyle(theme.inkTertiary)
                    )
                    .textFieldStyle(.plain)
                    .versoText(.callout)
                    .foregroundStyle(theme.ink)

                    durationField(payload)
                }

                Spacer(minLength: 0)

                controls(state: state, hasFinished: hasFinished, payload: payload.wrappedValue)
            }
            .padding(.vertical, Layout.Space.tight)
            .task {
                // Auto-start is what makes a rest timer on a template useful
                // rather than one more thing to remember to tap.
                if payload.wrappedValue.autoStart,
                   timers.state(for: block.id) == nil,
                   !timers.justFinished.contains(block.id) {
                    await timers.requestNotificationPermission()
                    start(payload.wrappedValue)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Dial

    private func dial(state: RestTimerState?, hasFinished: Bool, payload: TimerPayload) -> some View {
        ZStack {
            Circle()
                .strokeBorder(theme.rule, lineWidth: Layout.hairline * 4)

            Circle()
                .trim(from: 0, to: state?.fractionElapsed ?? (hasFinished ? 1 : 0))
                .stroke(
                    hasFinished ? theme.accent : theme.inkSecondary,
                    style: StrokeStyle(lineWidth: Layout.hairline * 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(motion.animation(.snap), value: state?.fractionElapsed)

            Text(remainingText(state: state, hasFinished: hasFinished, payload: payload))
                .versoText(.metadata)
                .foregroundStyle(hasFinished ? theme.accent : theme.ink)
                .monospacedDigit()
        }
        .frame(width: Layout.Space.vast, height: Layout.Space.vast)
        .accessibilityHidden(true)
    }

    private func remainingText(state: RestTimerState?, hasFinished: Bool, payload: TimerPayload) -> String {
        if hasFinished { return String(localized: "Done") }
        guard let state else { return payload.duration.timerClockText }
        // Reading `timers.tick` is what redraws this once a second.
        _ = timers.tick
        return state.remaining().timerClockText
    }

    // MARK: - Duration

    @ViewBuilder
    private func durationField(_ payload: Binding<TimerPayload>) -> some View {
        if isEditingDuration {
            HStack(spacing: Layout.Space.tight) {
                TextField("Seconds", text: Binding(
                    get: { String(Int(payload.wrappedValue.duration)) },
                    set: { payload.wrappedValue.duration = max(1, Double(Int($0) ?? 90)) }
                ))
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .fixedSize()

                Text("seconds")
            }
            .versoText(.metadata)
            .foregroundStyle(theme.inkSecondary)
            .accessibilityLabel(Text("Duration in seconds"))
        } else {
            Button {
                isEditingDuration = true
            } label: {
                Text(payload.wrappedValue.duration.timerClockText)
                    .versoText(.metadata)
                    .foregroundStyle(theme.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Duration"))
            .accessibilityValue(Text(payload.wrappedValue.duration.spokenDuration))
            .accessibilityHint(Text("Double tap to change"))
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private func controls(state: RestTimerState?, hasFinished: Bool, payload: TimerPayload) -> some View {
        if hasFinished {
            Button {
                timers.acknowledge(blockID: block.id)
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("\(payload.label.isEmpty ? String(localized: "Timer") : payload.label) finished. Reset"))
        } else if let state {
            HStack(spacing: Layout.Space.tight) {
                Button {
                    if state.isPaused {
                        timers.resume(blockID: block.id, sound: payload.sound, label: payload.label)
                    } else {
                        timers.pause(blockID: block.id)
                    }
                } label: {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text(state.isPaused ? "Resume" : "Pause"))
                .accessibilityValue(Text(state.remaining().spokenDuration))

                Button {
                    timers.stop(blockID: block.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("Stop"))
            }
            .foregroundStyle(theme.ink)
        } else {
            Button {
                Task {
                    await timers.requestNotificationPermission()
                    start(payload)
                }
            } label: {
                Image(systemName: "play.fill")
                    .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                    .contentShape(.rect)
            }
            .foregroundStyle(theme.accent)
            .accessibilityLabel(Text("Start"))
            .accessibilityValue(Text(payload.duration.spokenDuration))
        }
    }

    private func start(_ payload: TimerPayload) {
        motion.run(.snap) {
            timers.start(
                blockID: block.id,
                duration: payload.duration,
                sound: payload.sound,
                label: payload.label
            )
        }
    }
}
