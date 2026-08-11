import SwiftUI

/// The checklist editor.
///
/// It renders whatever sections `ChecklistPayload.sections()` produces and
/// whatever fields `itemFields` names. It contains no knowledge of aisles,
/// packing, or any other use case — a grocery list and a packing list are the
/// same code path with different JSON.
struct ChecklistBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion
    @FocusState private var focusedItem: UUID?

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<ChecklistPayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.regular) {
                ForEach(payload.wrappedValue.sections()) { section in
                    sectionView(section, payload: payload)
                }

                // With grouping on, every section has its own add button, so a
                // trailing one would have no group to file into.
                if payload.wrappedValue.groupBy != .group {
                    addButton(group: nil, payload: payload)
                }
            }
            .animation(motion.animation(.settle), value: payload.wrappedValue.items)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionView(
        _ section: ChecklistPayload.Section,
        payload: Binding<ChecklistPayload>
    ) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.snug) {
            if let title = section.title {
                Text(title)
                    .versoText(.metadata)
                    .foregroundStyle(theme.inkSecondary)
                    .accessibilityAddTraits(.isHeader)
            }

            ForEach(section.items) { item in
                itemRow(item, payload: payload)
            }

            if payload.wrappedValue.groupBy == .group {
                addButton(group: section.id, payload: payload)
            }
        }
    }

    // MARK: - Item

    @ViewBuilder
    private func itemRow(_ item: ChecklistPayload.Item, payload: Binding<ChecklistPayload>) -> some View {
        if let index = payload.wrappedValue.items.firstIndex(where: { $0.id == item.id }) {
            VStack(alignment: .leading, spacing: Layout.Space.hair) {
                HStack(alignment: .firstTextBaseline, spacing: Layout.Space.cosy) {
                    checkbox(item, payload: payload)

                    TextField(
                        "Item",
                        text: payload.items[index].label,
                        prompt: Text("Item").foregroundStyle(theme.inkTertiary),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .versoText(.body)
                    .foregroundStyle(item.checked ? theme.inkMuted : theme.ink)
                    .strikethrough(item.checked, color: theme.inkMuted)
                    .focused($focusedItem, equals: item.id)
                    .onSubmit { insertItem(group: item.group, after: index, payload: payload) }

                    quantityFields(index: index, payload: payload)
                }

                if payload.wrappedValue.shows(.note) {
                    noteField(index: index, payload: payload)
                }
            }
            .padding(.vertical, Layout.Space.hair)
        }
    }

    private func checkbox(_ item: ChecklistPayload.Item, payload: Binding<ChecklistPayload>) -> some View {
        Button {
            motion.run(.snap) {
                payload.wrappedValue.setChecked(!item.checked, itemID: item.id)
            }
        } label: {
            Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                .font(.system(size: Layout.checkboxSize))
                .foregroundStyle(item.checked ? theme.accent : theme.inkSecondary)
                .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.label.isEmpty ? String(localized: "Untitled item") : item.label))
        .accessibilityValue(Text(item.checked ? "Checked" : "Not checked"))
        .accessibilityAddTraits(item.checked ? [.isSelected] : [])
        .accessibilityHint(Text("Double tap to toggle"))
    }

    @ViewBuilder
    private func quantityFields(index: Int, payload: Binding<ChecklistPayload>) -> some View {
        HStack(spacing: Layout.Space.snug) {
            if payload.wrappedValue.shows(.quantity) {
                TextField(
                    "Qty",
                    value: payload.items[index].quantity,
                    format: .number.precision(.fractionLength(0...2))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: Layout.Space.vast)
                .accessibilityLabel(Text("Quantity"))
            }

            if payload.wrappedValue.shows(.unit) {
                TextField("Unit", text: Binding(
                    get: { payload.wrappedValue.items[index].unit ?? "" },
                    set: { payload.wrappedValue.items[index].unit = $0.isEmpty ? nil : $0 }
                ))
                .frame(width: Layout.Space.airy)
                .accessibilityLabel(Text("Unit"))
            }

            if payload.wrappedValue.shows(.price) {
                TextField(
                    "Price",
                    value: payload.items[index].price,
                    format: .currency(code: currencyCode(for: payload.wrappedValue.items[index]))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: Layout.Space.vast * 1.5)
                .accessibilityLabel(Text("Price"))
            }
        }
        .textFieldStyle(.plain)
        .versoText(.metadata)
        .foregroundStyle(theme.inkSecondary)
    }

    private func noteField(index: Int, payload: Binding<ChecklistPayload>) -> some View {
        TextField(
            "Note",
            text: Binding(
                get: { payload.wrappedValue.items[index].note ?? "" },
                set: { payload.wrappedValue.items[index].note = $0.isEmpty ? nil : $0 }
            ),
            prompt: Text("Note").foregroundStyle(theme.inkTertiary),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .versoText(.footnote)
        .foregroundStyle(theme.inkSecondary)
        .padding(.leading, Layout.minimumHitTarget + Layout.Space.cosy)
        .accessibilityLabel(Text("Note"))
    }

    // MARK: - Adding

    private func addButton(group: String?, payload: Binding<ChecklistPayload>) -> some View {
        Button {
            insertItem(group: group, after: payload.wrappedValue.items.count - 1, payload: payload)
        } label: {
            Label("Add item", systemImage: "plus")
                .versoText(.callout)
                .foregroundStyle(theme.inkSecondary)
                .padding(.leading, Layout.minimumHitTarget)
                .frame(minHeight: Layout.minimumHitTarget, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func insertItem(group: String?, after index: Int, payload: Binding<ChecklistPayload>) {
        // A section's add button files the new item into that section. That is
        // the engine honouring `groupBy`, not knowledge of what the group means.
        let item = ChecklistPayload.Item(group: group)
        let target = min(max(index + 1, 0), payload.wrappedValue.items.count)
        payload.wrappedValue.items.insert(item, at: target)
        focusedItem = item.id
    }

    private func currencyCode(for item: ChecklistPayload.Item) -> String {
        item.currency ?? Locale.current.currency?.identifier ?? "USD"
    }
}
