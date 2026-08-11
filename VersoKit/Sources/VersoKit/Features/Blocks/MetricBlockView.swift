import SwiftData
import SwiftUI

/// A single reading, its history, and whether it is the best one yet.
///
/// Also, when the JSON asks for them: the last reading in this series, a
/// decomposition of the value into available units, a catalog picker, and a
/// countdown started on commit. Every one of those is a property of *a metric*
/// — none of them mentions an exercise, a barbell or a template.
struct MetricBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion
    @Environment(\.modelContext) private var context
    @Environment(RestTimerService.self) private var timers
    @Environment(HapticEngine.self) private var haptics

    @State private var isPersonalBest = false
    @State private var history: [MetricPoint] = []
    @State private var previous: MetricEntry?
    @State private var isPickingFromCatalog = false

    private var store: MetricSeriesStore { MetricSeriesStore(context: context) }

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<MetricPayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.tight) {
                header(payload)

                if payload.wrappedValue.showsPreviousEntry, let previous {
                    previousRow(previous, unit: payload.wrappedValue.unit)
                }

                reading(payload)

                if let decomposition = payload.wrappedValue.decomposition,
                   let value = payload.wrappedValue.value {
                    decompositionRow(decomposition.decompose(value))
                }

                if let state = timers.state(for: block.id) {
                    restRow(state)
                }

                if !history.isEmpty {
                    MetricSparkline(points: history)
                }
            }
            .padding(.vertical, Layout.Space.tight)
            .sheet(isPresented: $isPickingFromCatalog) {
                if let catalog = CatalogLibrary.shared.catalog(id: payload.wrappedValue.catalogID) {
                    CatalogPickerSheet(catalog: catalog) { entry in
                        apply(entry, to: payload)
                    }
                }
            }
            .task(id: payload.wrappedValue.seriesID) {
                refresh(payload.wrappedValue)
            }
            .onChange(of: payload.wrappedValue.value) { oldValue, newValue in
                commit(payload)
                startRestTimerIfNeeded(payload.wrappedValue, previousValue: oldValue, newValue: newValue)
            }
            .onChange(of: payload.wrappedValue.label) { _, newValue in
                if payload.wrappedValue.seriesID.isEmpty {
                    payload.wrappedValue.seriesID = MetricPayload.slug(newValue)
                }
            }
            .onChange(of: isPersonalBest) { wasBest, isBest in
                if isBest && !wasBest { haptics.play(.personalRecord) }
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

            if payload.wrappedValue.catalogID != nil {
                Button {
                    isPickingFromCatalog = true
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                        .contentShape(.rect)
                }
                .foregroundStyle(theme.accent)
                .accessibilityLabel(Text("Choose from the library"))
            }

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

    /// Section 7 asks for last session's numbers to be visible *while* logging,
    /// not a tap away.
    private func previousRow(_ entry: MetricEntry, unit: String) -> some View {
        let formatted = entry.value.formatted(.number.precision(.fractionLength(0...2)))
        let when = entry.recordedAt.formatted(date: .abbreviated, time: .omitted)

        return Text("Last: \(formatted) \(unit.isEmpty ? "" : unit) · \(when)")
            .versoText(.metadata)
            .foregroundStyle(theme.inkSecondary)
            .accessibilityLabel(Text("Previous reading \(formatted) \(unit), \(when)"))
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

    /// Plate maths, said generically.
    private func decompositionRow(_ result: DecompositionResult) -> some View {
        HStack(spacing: Layout.Space.snug) {
            Image(systemName: "circle.hexagongrid")
                .foregroundStyle(theme.inkSecondary)

            Text(result.displayText)
                .versoText(.metadata)
                .foregroundStyle(theme.inkSecondary)

            if !result.isExact {
                Text("(nearest: \(result.achieved.formatted(.number.precision(.fractionLength(0...2)))))")
                    .versoText(.metadata)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Loading"))
        .accessibilityValue(Text(result.displayText))
    }

    private func restRow(_ state: RestTimerState) -> some View {
        HStack(spacing: Layout.Space.snug) {
            Image(systemName: "timer")
            Text(state.remaining(at: timers.tick).timerClockText)
                .monospacedDigit()
            Spacer(minLength: 0)
            Button("Stop") { timers.stop(blockID: block.id) }
                .versoText(.metadata)
        }
        .versoText(.metadata)
        .foregroundStyle(theme.accent)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Rest remaining"))
        .accessibilityValue(Text(state.remaining(at: timers.tick).spokenDuration))
    }

    // MARK: - Catalog

    private func apply(_ entry: Catalog.Entry, to payload: Binding<MetricPayload>) {
        payload.wrappedValue.label = entry.name
        payload.wrappedValue.seriesID = entry.id
        if let unit = entry.unit { payload.wrappedValue.unit = unit }
    }

    // MARK: - Series

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

    /// A metric with a cooldown starts it the moment a reading appears — which
    /// for a strength template means the rest timer starts on set completion,
    /// with nothing to tap.
    private func startRestTimerIfNeeded(_ payload: MetricPayload, previousValue: Double?, newValue: Double?) {
        guard let seconds = payload.restTimerSeconds, seconds > 0,
              newValue != nil, previousValue == nil
        else { return }

        timers.start(
            blockID: block.id,
            duration: seconds,
            sound: .chime,
            label: payload.label.isEmpty ? String(localized: "Rest") : payload.label
        )
    }

    private func refresh(_ payload: MetricPayload) {
        guard !payload.seriesID.isEmpty else {
            history = []
            previous = nil
            isPersonalBest = false
            return
        }

        let entries = store.entries(seriesID: payload.seriesID, in: .quarter)
        history = MetricAggregator.daily(entries, using: .maximum)

        let noteID = block.note?.id
        let own = noteID.flatMap {
            store.findEntry(seriesID: payload.seriesID, groupID: groupID(for: payload), noteID: $0)
        }

        // "Last" means the most recent reading that is not this one — otherwise
        // every metric would report itself as its own previous value.
        previous = store.entries(seriesID: payload.seriesID)
            .filter { $0.id != own?.id }
            .last

        if let value = payload.value {
            isPersonalBest = store.isPersonalBest(value, seriesID: payload.seriesID, excluding: own?.id)
        } else {
            isPersonalBest = false
        }
    }

    private static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return cleaned.isEmpty ? nil : Double(cleaned)
    }
}
