import SwiftUI

struct ListBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @FocusState private var focusedItem: UUID?

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<ListPayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.tight) {
                ForEach(Array(payload.wrappedValue.items.enumerated()), id: \.element.id) { index, item in
                    row(index: index, item: item, payload: payload)
                }

                addButton(payload)
            }
            .contextMenu {
                Picker("Style", selection: payload.style) {
                    ForEach(ListPayload.Style.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }
        }
    }

    private func row(index: Int, item: ListPayload.Item, payload: Binding<ListPayload>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.Space.snug) {
            marker(index: index, style: payload.wrappedValue.style)

            TextField(
                "Item",
                text: payload.items[index].text,
                prompt: Text("Item").foregroundStyle(theme.inkTertiary),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .versoText(.body)
            .foregroundStyle(theme.ink)
            .focused($focusedItem, equals: item.id)
            .onSubmit { insertItem(after: index, payload: payload) }
            // Emptying a row and submitting removes it, which is how every
            // list editor on the platform behaves.
            .onChange(of: focusedItem) { previous, _ in
                guard previous == item.id, item.text.isEmpty, payload.wrappedValue.items.count > 1 else { return }
                payload.wrappedValue.items.removeAll { $0.id == item.id }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func marker(index: Int, style: ListPayload.Style) -> some View {
        switch style {
        case .bullet:
            Text(verbatim: "•")
                .versoText(.body)
                .foregroundStyle(theme.inkSecondary)
                .accessibilityHidden(true)
        case .numbered:
            Text(verbatim: "\(index + 1).")
                .versoText(.metadata)
                .foregroundStyle(theme.inkSecondary)
                .frame(minWidth: Layout.Space.loose, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func addButton(_ payload: Binding<ListPayload>) -> some View {
        Button {
            insertItem(after: payload.wrappedValue.items.count - 1, payload: payload)
        } label: {
            Label("Add item", systemImage: "plus")
                .versoText(.callout)
                .foregroundStyle(theme.inkSecondary)
                .frame(minHeight: Layout.minimumHitTarget, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func insertItem(after index: Int, payload: Binding<ListPayload>) {
        let item = ListPayload.Item()
        let target = min(max(index + 1, 0), payload.wrappedValue.items.count)
        payload.wrappedValue.items.insert(item, at: target)
        focusedItem = item.id
    }
}
