import SwiftUI

struct ProgressBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<ProgressPayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.snug) {
                header(payload)
                indicator(payload.wrappedValue)
            }
            .padding(.vertical, Layout.Space.tight)
            .contextMenu {
                Picker("Style", selection: payload.style) {
                    ForEach(ProgressPayload.Style.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }
            .animation(motion.animation(.settle), value: payload.wrappedValue.fraction)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(payload.wrappedValue.label.isEmpty
                                     ? String(localized: "Progress")
                                     : payload.wrappedValue.label))
            .accessibilityValue(Text(
                "\(payload.wrappedValue.current.formatted(.number.precision(.fractionLength(0...2)))) of \(payload.wrappedValue.target.formatted(.number.precision(.fractionLength(0...2))))"
            ))
        }
    }

    private func header(_ payload: Binding<ProgressPayload>) -> some View {
        HStack(spacing: Layout.Space.snug) {
            TextField(
                "Label",
                text: payload.label,
                prompt: Text("Progress").foregroundStyle(theme.inkTertiary)
            )
            .textFieldStyle(.plain)
            .versoText(.callout)
            .foregroundStyle(theme.ink)

            Spacer(minLength: 0)

            stepper(payload)
        }
    }

    private func stepper(_ payload: Binding<ProgressPayload>) -> some View {
        HStack(spacing: Layout.Space.tight) {
            Button {
                motion.run(.snap) {
                    payload.wrappedValue.current = max(0, payload.wrappedValue.current - 1)
                }
            } label: {
                Image(systemName: "minus")
                    .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Decrease"))

            Text("\(payload.wrappedValue.current.formatted(.number.precision(.fractionLength(0...2)))) / \(payload.wrappedValue.target.formatted(.number.precision(.fractionLength(0...2))))")
                .versoText(.metadata)
                .foregroundStyle(theme.inkSecondary)
                .monospacedDigit()
                .accessibilityHidden(true)

            Button {
                motion.run(.snap) {
                    payload.wrappedValue.current += 1
                }
            } label: {
                Image(systemName: "plus")
                    .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Increase"))
        }
        .foregroundStyle(theme.ink)
    }

    @ViewBuilder
    private func indicator(_ payload: ProgressPayload) -> some View {
        switch payload.style {
        case .bar:
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.inset)
                    Capsule()
                        .fill(payload.isComplete ? theme.accent : theme.inkSecondary)
                        .frame(width: proxy.size.width * payload.fraction)
                }
            }
            .frame(height: Layout.Space.snug)

        case .ring:
            ZStack {
                Circle().strokeBorder(theme.inset, lineWidth: Layout.hairline * 6)
                Circle()
                    .trim(from: 0, to: payload.fraction)
                    .stroke(
                        payload.isComplete ? theme.accent : theme.inkSecondary,
                        style: StrokeStyle(lineWidth: Layout.hairline * 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: Layout.Space.vast, height: Layout.Space.vast)

        case .dots:
            // One mark per unit, but only while they stay countable at a
            // glance. Past that a bar tells the truth better than 200 dots.
            let total = Int(payload.target.rounded())
            if total > 0 && total <= 20 {
                HStack(spacing: Layout.Space.tight) {
                    ForEach(0..<total, id: \.self) { index in
                        Circle()
                            .fill(Double(index) < payload.current ? theme.accent : theme.inset)
                            .frame(width: Layout.Space.cosy, height: Layout.Space.cosy)
                    }
                }
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.inset)
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: proxy.size.width * payload.fraction)
                    }
                }
                .frame(height: Layout.Space.snug)
            }
        }
    }
}
