import SwiftUI

struct DividerBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<DividerPayload>) in
            mark(for: payload.wrappedValue.style)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Layout.Space.cosy)
                .contentShape(.rect)
                .contextMenu {
                    Picker("Style", selection: payload.style) {
                        ForEach(DividerPayload.Style.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Divider"))
                .accessibilityValue(Text(payload.wrappedValue.style.displayName))
        }
    }

    @ViewBuilder
    private func mark(for style: DividerPayload.Style) -> some View {
        switch style {
        case .rule:
            Rectangle()
                .fill(theme.rule)
                .frame(height: Layout.hairline)
        case .dots:
            HStack(spacing: Layout.Space.regular) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(theme.inkSecondary)
                        .frame(width: Layout.Space.tight, height: Layout.Space.tight)
                }
            }
        case .fleuron:
            Text(verbatim: "❧")
                .versoText(.heading)
                .foregroundStyle(theme.inkSecondary)
        case .space:
            Color.clear
                .frame(height: Layout.Space.loose)
        }
    }
}
