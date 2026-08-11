import SwiftUI

struct ScheduleBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion
    @Environment(ScheduleService.self) private var schedule

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<SchedulePayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.snug) {
                TextField(
                    "Label",
                    text: payload.label,
                    prompt: Text("Reminder").foregroundStyle(theme.inkTertiary)
                )
                .textFieldStyle(.plain)
                .versoText(.callout)
                .foregroundStyle(theme.ink)

                dueRow(payload)

                if payload.wrappedValue.dueAt != nil {
                    recurrenceRow(payload)
                    alarmsRow(payload)
                }

                if let warning = schedule.warning {
                    inactiveNotice(warning)
                } else if !schedule.isAuthorized {
                    permissionNotice
                }
            }
            .padding(.vertical, Layout.Space.tight)
            .task {
                await schedule.refreshAuthorizationStatus()
            }
            .onChange(of: payload.wrappedValue) { _, _ in
                Task { await schedule.refresh() }
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func dueRow(_ payload: Binding<SchedulePayload>) -> some View {
        if let due = payload.wrappedValue.dueAt {
            HStack {
                DatePicker(
                    "Due",
                    selection: Binding(
                        get: { due },
                        set: { payload.wrappedValue.dueAt = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()

                Spacer(minLength: 0)

                Button {
                    motion.run(.settle) { payload.wrappedValue.dueAt = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                        .contentShape(.rect)
                }
                .foregroundStyle(theme.inkTertiary)
                .accessibilityLabel(Text("Remove due date"))
            }
        } else {
            Button {
                motion.run(.settle) {
                    payload.wrappedValue.dueAt = Date().addingTimeInterval(3600)
                }
            } label: {
                Label("Set a time", systemImage: "calendar.badge.plus")
                    .versoText(.callout)
                    .foregroundStyle(theme.accent)
                    .frame(minHeight: Layout.minimumHitTarget, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func recurrenceRow(_ payload: Binding<SchedulePayload>) -> some View {
        Menu {
            Button("Never") { payload.wrappedValue.recurrence = nil }
            ForEach(Recurrence.Frequency.allCases, id: \.self) { frequency in
                Button(String(localized: frequency.displayName)) {
                    payload.wrappedValue.recurrence = Recurrence(frequency: frequency)
                }
            }
        } label: {
            HStack(spacing: Layout.Space.snug) {
                Image(systemName: "repeat")
                Text(payload.wrappedValue.recurrence?.displayDescription ?? String(localized: "Doesn't repeat"))
                Spacer(minLength: 0)
            }
            .versoText(.metadata)
            .foregroundStyle(theme.inkSecondary)
            .frame(minHeight: Layout.minimumHitTarget)
            .contentShape(.rect)
        }
        .accessibilityLabel(Text("Repeat"))
        .accessibilityValue(Text(payload.wrappedValue.recurrence?.displayDescription ?? String(localized: "Never")))
    }

    private func alarmsRow(_ payload: Binding<SchedulePayload>) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.tight) {
            ForEach(payload.wrappedValue.alarms) { alarm in
                HStack(spacing: Layout.Space.snug) {
                    Image(systemName: "bell")
                        .foregroundStyle(theme.inkSecondary)
                    Text(alarm.displayName)
                        .versoText(.metadata)
                        .foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 0)
                    Button {
                        motion.run(.settle) {
                            payload.wrappedValue.alarms.removeAll { $0.id == alarm.id }
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                            .contentShape(.rect)
                    }
                    .foregroundStyle(theme.inkTertiary)
                    .accessibilityLabel(Text("Remove alarm \(alarm.displayName)"))
                }
            }

            Menu {
                ForEach(SchedulePayload.Alarm.presets, id: \.self) { offset in
                    Button(SchedulePayload.Alarm(offset: offset).displayName) {
                        motion.run(.settle) {
                            payload.wrappedValue.alarms.append(SchedulePayload.Alarm(offset: offset))
                        }
                    }
                }
            } label: {
                Label("Add alarm", systemImage: "plus")
                    .versoText(.metadata)
                    .foregroundStyle(theme.accent)
                    .frame(minHeight: Layout.minimumHitTarget, alignment: .leading)
                    .contentShape(.rect)
            }
        }
    }

    // MARK: - Notices

    private func inactiveNotice(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .versoText(.footnote)
            .foregroundStyle(theme.inkSecondary)
            .padding(Layout.Space.snug)
            .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.tight))
    }

    private var permissionNotice: some View {
        Button {
            Task { await schedule.requestAuthorization() }
        } label: {
            Label(
                "Verso can't send reminders yet. Tap to allow notifications.",
                systemImage: "bell.badge"
            )
            .versoText(.footnote)
            .foregroundStyle(theme.accent)
            .padding(Layout.Space.snug)
            .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.tight))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
