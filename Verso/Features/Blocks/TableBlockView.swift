import SwiftUI

/// A small table.
///
/// Scrolls horizontally inside itself rather than widening the page — the
/// measure is the measure, and a table is not a reason to break it.
struct TableBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    private static let columnWidth: CGFloat = 108

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<TablePayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.snug) {
                TextField(
                    "Caption",
                    text: payload.caption,
                    prompt: Text("Table").foregroundStyle(theme.inkTertiary)
                )
                .textFieldStyle(.plain)
                .versoText(.callout)
                .foregroundStyle(theme.inkSecondary)

                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        headerRow(payload)
                        ForEach(Array(payload.wrappedValue.rows.enumerated()), id: \.element.id) { rowIndex, row in
                            bodyRow(rowIndex: rowIndex, row: row, payload: payload)
                        }
                    }
                }
                .scrollIndicators(.automatic)

                footer(payload)
            }
            .padding(.vertical, Layout.Space.tight)
            .animation(motion.animation(.settle), value: payload.wrappedValue.rows.count)
            .animation(motion.animation(.settle), value: payload.wrappedValue.columns.count)
        }
    }

    // MARK: - Rows

    /// The title is an editable field and the column's type and deletion live
    /// behind a separate button. A `TextField` used as a `Menu` label cannot be
    /// typed into — the menu swallows the tap.
    private func headerRow(_ payload: Binding<TablePayload>) -> some View {
        GridRow {
            ForEach(Array(payload.wrappedValue.columns.enumerated()), id: \.element.id) { index, column in
                HStack(spacing: Layout.Space.tight) {
                    TextField(
                        "Column",
                        text: payload.columns[index].title,
                        prompt: Text("Column").foregroundStyle(theme.inkTertiary)
                    )
                    .textFieldStyle(.plain)
                    .accessibilityLabel(Text("Column \(index + 1) title"))

                    Menu {
                        Picker("Type", selection: payload.columns[index].kind) {
                            ForEach(TablePayload.ColumnKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        Button("Delete Column", role: .destructive) {
                            removeColumn(at: index, payload: payload)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(minWidth: Layout.Space.regular, minHeight: Layout.minimumHitTarget)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(Text("Options for column \(column.title.isEmpty ? "\(index + 1)" : column.title)"))
                }
                .versoText(.metadata)
                .foregroundStyle(theme.inkSecondary)
                .frame(width: Self.columnWidth, alignment: .leading)
                .padding(Layout.Space.tight)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.rule).frame(height: Layout.hairline)
        }
    }

    private func bodyRow(rowIndex: Int, row: TablePayload.Row, payload: Binding<TablePayload>) -> some View {
        GridRow {
            ForEach(Array(payload.wrappedValue.columns.enumerated()), id: \.element.id) { columnIndex, column in
                cell(rowIndex: rowIndex, columnIndex: columnIndex, kind: column.kind, payload: payload)
                    .frame(width: Self.columnWidth, alignment: .leading)
                    .padding(Layout.Space.tight)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.rule.opacity(0.5)).frame(height: Layout.hairline)
        }
        .contextMenu {
            // Section 7's one-tap repeat set. Generic: duplicating a row copies
            // its values, which is what "same again" means for any table.
            Button {
                duplicateRow(at: rowIndex, payload: payload)
            } label: {
                Label("Repeat Row", systemImage: "plus.square.on.square")
            }
            Button("Delete Row", role: .destructive) {
                removeRow(at: rowIndex, payload: payload)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                duplicateRow(at: rowIndex, payload: payload)
            } label: {
                Label("Repeat", systemImage: "plus.square.on.square")
            }
        }
    }

    @ViewBuilder
    private func cell(
        rowIndex: Int,
        columnIndex: Int,
        kind: TablePayload.ColumnKind,
        payload: Binding<TablePayload>
    ) -> some View {
        let cellBinding = payload.rows[rowIndex].cells[columnIndex]

        switch kind {
        case .text:
            TextField("", text: Binding(
                get: { cellBinding.wrappedValue.text ?? "" },
                set: { cellBinding.wrappedValue.text = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.plain)
            .versoText(.callout)
            .foregroundStyle(theme.ink)

        case .number:
            TextField("", text: Binding(
                get: { cellBinding.wrappedValue.number.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "" },
                set: { cellBinding.wrappedValue.number = Self.parse($0) }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(.plain)
            .versoText(.callout)
            .foregroundStyle(theme.ink)
            .monospacedDigit()

        case .date:
            DatePicker(
                "",
                selection: Binding(
                    get: { cellBinding.wrappedValue.date ?? Date() },
                    set: { cellBinding.wrappedValue.date = $0 }
                ),
                displayedComponents: .date
            )
            .labelsHidden()

        case .checkbox:
            Button {
                motion.run(.snap) {
                    cellBinding.wrappedValue.checked = !(cellBinding.wrappedValue.checked ?? false)
                }
            } label: {
                Image(systemName: (cellBinding.wrappedValue.checked ?? false) ? "checkmark.square.fill" : "square")
                    .foregroundStyle((cellBinding.wrappedValue.checked ?? false) ? theme.accent : theme.inkSecondary)
                    .frame(minHeight: Layout.minimumHitTarget, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text((cellBinding.wrappedValue.checked ?? false) ? "Checked" : "Not checked"))
        }
    }

    // MARK: - Structure

    private func footer(_ payload: Binding<TablePayload>) -> some View {
        HStack(spacing: Layout.Space.regular) {
            Button {
                motion.run(.settle) {
                    payload.wrappedValue.rows.append(
                        TablePayload.Row(cells: Array(repeating: .init(), count: payload.wrappedValue.columns.count))
                    )
                }
            } label: {
                Label("Row", systemImage: "plus")
            }
            .accessibilityLabel(Text("Add row"))

            Button {
                motion.run(.settle) {
                    payload.wrappedValue.columns.append(TablePayload.Column())
                    payload.wrappedValue = payload.wrappedValue.normalized()
                }
            } label: {
                Label("Column", systemImage: "plus")
            }
            .accessibilityLabel(Text("Add column"))
        }
        .versoText(.metadata)
        .foregroundStyle(theme.inkSecondary)
        .frame(minHeight: Layout.minimumHitTarget)
    }

    /// Copies a row's values into a new one directly beneath it, clearing any
    /// checkboxes — repeating a set means doing it again, not having done it.
    private func duplicateRow(at index: Int, payload: Binding<TablePayload>) {
        guard payload.wrappedValue.rows.indices.contains(index) else { return }
        let source = payload.wrappedValue.rows[index]

        let copy = TablePayload.Row(cells: zip(source.cells, payload.wrappedValue.columns).map { cell, column in
            var cell = cell
            if column.kind == .checkbox { cell.checked = false }
            return cell
        })

        motion.run(.settle) {
            payload.wrappedValue.rows.insert(copy, at: index + 1)
        }
    }

    private func removeRow(at index: Int, payload: Binding<TablePayload>) {
        guard payload.wrappedValue.rows.indices.contains(index) else { return }
        motion.run(.settle) {
            payload.wrappedValue.rows.remove(at: index)
        }
    }

    private func removeColumn(at index: Int, payload: Binding<TablePayload>) {
        guard payload.wrappedValue.columns.indices.contains(index) else { return }
        motion.run(.settle) {
            payload.wrappedValue.columns.remove(at: index)
            for rowIndex in payload.wrappedValue.rows.indices
            where payload.wrappedValue.rows[rowIndex].cells.indices.contains(index) {
                payload.wrappedValue.rows[rowIndex].cells.remove(at: index)
            }
            payload.wrappedValue = payload.wrappedValue.normalized()
        }
    }

    private static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return cleaned.isEmpty ? nil : Double(cleaned)
    }
}
