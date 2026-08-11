import SwiftUI

struct HeadingBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<HeadingPayload>) in
            HStack(alignment: .firstTextBaseline, spacing: Layout.Space.snug) {
                TextField(
                    "Heading",
                    text: payload.text,
                    prompt: Text("Heading").foregroundStyle(theme.inkTertiary),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .versoText(role(for: payload.wrappedValue.level))
                .foregroundStyle(theme.ink)

                levelMenu(payload)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(String(localized: payload.wrappedValue.level.displayName)))
        }
    }

    private func levelMenu(_ payload: Binding<HeadingPayload>) -> some View {
        Menu {
            Picker("Level", selection: payload.level) {
                ForEach(HeadingPayload.Level.allCases, id: \.self) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(verbatim: "H\(payload.wrappedValue.level.rawValue)")
                .versoText(.metadata)
                .foregroundStyle(theme.inkSecondary)
                .frame(minWidth: Layout.Space.loose, minHeight: Layout.minimumHitTarget)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text("Heading level"))
        .accessibilityValue(Text(payload.wrappedValue.level.displayName))
    }

    /// Heading levels 1–3 map onto the 26 / 20 / 17 steps of the type scale.
    private func role(for level: HeadingPayload.Level) -> Typography.Role {
        switch level {
        case .one: .title
        case .two: .heading
        case .three: .body
        }
    }
}
