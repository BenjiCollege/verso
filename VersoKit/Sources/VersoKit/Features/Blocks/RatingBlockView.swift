import SwiftUI

struct RatingBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<RatingPayload>) in
            HStack(spacing: Layout.Space.cosy) {
                TextField(
                    "Label",
                    text: payload.label,
                    prompt: Text("Rating").foregroundStyle(theme.inkTertiary)
                )
                .textFieldStyle(.plain)
                .versoText(.callout)
                .foregroundStyle(theme.ink)

                Spacer(minLength: 0)

                marks(payload)
            }
            .padding(.vertical, Layout.Space.tight)
            .contextMenu {
                Picker("Symbol", selection: payload.symbol) {
                    ForEach(RatingPayload.Symbol.allCases, id: \.self) { symbol in
                        Text(symbol.displayName).tag(symbol)
                    }
                }
                Picker("Scale", selection: payload.scale) {
                    ForEach([3, 4, 5, 7, 10], id: \.self) { scale in
                        Text("Out of \(scale)").tag(scale)
                    }
                }
            }
            // One control for the whole rating, so VoiceOver users adjust it
            // by swiping rather than hunting for the fourth star.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(payload.wrappedValue.label.isEmpty
                                     ? String(localized: "Rating")
                                     : payload.wrappedValue.label))
            .accessibilityValue(Text(accessibilityValue(payload.wrappedValue)))
            .accessibilityAdjustableAction { direction in
                adjust(payload, direction: direction)
            }
        }
    }

    private func marks(_ payload: Binding<RatingPayload>) -> some View {
        let value = payload.wrappedValue.value ?? 0

        return HStack(spacing: Layout.Space.tight) {
            ForEach(1...payload.wrappedValue.scale, id: \.self) { mark in
                Button {
                    motion.run(.snap) {
                        // Tapping the current value clears it, which is the
                        // only way to get back to unrated.
                        payload.wrappedValue.value = (payload.wrappedValue.value == mark) ? nil : mark
                    }
                } label: {
                    Image(systemName: mark <= value
                          ? payload.wrappedValue.symbol.filledImage
                          : payload.wrappedValue.symbol.emptyImage)
                        .foregroundStyle(mark <= value ? theme.accent : theme.inkTertiary)
                        .frame(minWidth: Layout.minimumHitTarget / 1.5, minHeight: Layout.minimumHitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityHidden(true)
    }

    private func accessibilityValue(_ payload: RatingPayload) -> String {
        guard let value = payload.value else { return String(localized: "Not rated") }
        return String(localized: "\(value) out of \(payload.scale)")
    }

    private func adjust(_ payload: Binding<RatingPayload>, direction: AccessibilityAdjustmentDirection) {
        let current = payload.wrappedValue.value ?? 0
        let next = direction == .increment ? current + 1 : current - 1
        payload.wrappedValue.value = next < 1 ? nil : min(next, payload.wrappedValue.scale)
    }
}
