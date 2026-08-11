import SwiftData
import SwiftUI

/// A single reading, its history, and whether it is the best one yet.
///
/// Editing the number corrects this block's row in the series rather than
/// appending another, so the chart shows your bench press and not how many
/// times you tapped the field.
struct MetricBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion
    @Environment(\.modelContext) private var context

    @State private var isPersonalBest = false
    @State private var history: [MetricPoint] = []

    private var store: MetricSeriesStore { MetricSeriesStore(context: context) }

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<MetricPayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.tight) {
                header(payload)
                reading(payload)

                if !history.isEmpty {
                    MetricSparkline(points: history)
                }
            }
            .padding(.vertical, Layout.Space.tight)
            .task(id: payload.wrappedValue.seriesID) {
                refresh(payload.wrappedValue)
            }
            .onChange(of: payload.wrappedValue.value) { _, _ in
                commit(payload)
            }
            .onChange(of: payload.wrappedValue.label) { _, newValue in
                // A metric that has never been named derives its series from
                // the label, so naming it late still files it correctly.
                if payload.wrappedValue.seriesID.isEmpty {
                    payload.wrappedValue.seriesID = MetricPayload.slug(newValue)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Pieces

    private func header(_ payload: Binding<MetricPayload>) -> some View {
        HStack(spacing: Layout.Space.snug) {
            TextField(
                "Label",
                text: payload.label,
                prompt: Text("Measurement").foregroundStyle(theme.inkTertiary)
            )
            .textFieldStyle(.plain)
            .versoText(.callout)
            .foregroundStyle(theme.inkSecondary)

            if isPersonalBest {
                Label("Best", systemImage: "rosette")
                    .versoText(.metadata)
                    .foregroundStyle(theme.accent)
                    .transition(motion.transition(.reveal, motion: .scale.combined(with: .opacity)))
                    .accessibilityLabel(Text("Personal best"))
            }
        }
        .animation(motion.animation(.reveal), value: isPersonalBest)
    }

    private func reading(_ payload: Binding<MetricPayload>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.Space.snug) {
            TextField("Value", text: Binding(
                get: { payload.wrappedValue.value.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "" },
                set: { payload.wrappedValue.value = Self.parse($0) }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(.plain)
            .versoText(.title)
            .foregroundStyle(theme.ink)
            .fixedSize()
            .accessibilityLabel(Text("Value"))

            TextField("Unit", text: payload.unit, prompt: Text("unit").foregroundStyle(theme.inkTertiary))
                .textFieldStyle(.plain)
                .versoText(.metadata)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize()
                .accessibilityLabel(Text("Unit"))

            Spacer(minLength: 0)

            if let fraction = payload.wrappedValue.fractionOfTarget, let target = payload.wrappedValue.target {
                Text("\(Int((fraction * 100).rounded()))% of \(target.formatted(.number.precision(.fractionLength(0...2))))")
                    .versoText(.metadata)
                    .foregroundStyle(theme.inkSecondary)
            }
        }
    }

    // MARK: - Series

    /// The block's identity in the series. A template may set `groupID` — sets
    /// within an exercise — and when it doesn't, the block's own id serves,
    /// so two readings in one note never collide.
    private func groupID(for payload: MetricPayload) -> String {
        payload.groupID ?? block.id.uuidString
    }

    private func commit(_ payload: Binding<MetricPayload>) {
        var value = payload.wrappedValue
        if value.seriesID.isEmpty { value.seriesID = MetricPayload.slug(value.label) }
        if value.groupID == nil { value.groupID = block.id.uuidString }
        guard !value.seriesID.isEmpty, let noteID = block.note?.id else { return }

        payload.wrappedValue = value

        store.record(
            seriesID: value.seriesID,
            groupID: value.groupID,
            label: value.label,
            value: value.value,
            unit: value.unit,
            noteID: noteID
        )
        refresh(value)
    }

    private func refresh(_ payload: MetricPayload) {
        guard !payload.seriesID.isEmpty else {
            history = []
            isPersonalBest = false
            return
        }

        let entries = store.entries(seriesID: payload.seriesID, in: .quarter)
        history = MetricAggregator.daily(entries, using: .maximum)

        if let value = payload.value, let noteID = block.note?.id {
            let existing = store.findEntry(
                seriesID: payload.seriesID,
                groupID: groupID(for: payload),
                noteID: noteID
            )
            isPersonalBest = store.isPersonalBest(value, seriesID: payload.seriesID, excluding: existing?.id)
        } else {
            isPersonalBest = false
        }
    }

    private static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return cleaned.isEmpty ? nil : Double(cleaned)
    }
}
