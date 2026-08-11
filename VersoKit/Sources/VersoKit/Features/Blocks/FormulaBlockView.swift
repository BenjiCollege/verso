import SwiftUI

/// A number the note works out for itself.
///
/// The result is recomputed whenever anything the expression could have read
/// changes, which for now means whenever the note's modification date moves.
/// An expression that cannot be evaluated shows why, in words, rather than a
/// dash — a formula you cannot debug is a formula you delete.
struct FormulaBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context

    @State private var result: Double?
    @State private var failure: String?
    @State private var isEditingExpression = false

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<FormulaPayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.tight) {
                HStack(alignment: .firstTextBaseline, spacing: Layout.Space.snug) {
                    TextField(
                        "Label",
                        text: payload.label,
                        prompt: Text("Result").foregroundStyle(theme.inkTertiary)
                    )
                    .textFieldStyle(.plain)
                    .versoText(.callout)
                    .foregroundStyle(theme.inkSecondary)

                    Spacer(minLength: 0)

                    Text(resultText)
                        .versoText(.title)
                        .foregroundStyle(failure == nil ? theme.ink : theme.inkTertiary)
                        .monospacedDigit()
                }

                expressionField(payload)

                if let failure {
                    Text(failure)
                        .versoText(.footnote)
                        .foregroundStyle(theme.inkSecondary)
                }
            }
            .padding(.vertical, Layout.Space.tight)
            .onChange(of: payload.wrappedValue.expression) { _, _ in evaluate(payload.wrappedValue) }
            .onChange(of: block.note?.modifiedAt) { _, _ in evaluate(payload.wrappedValue) }
            .task { evaluate(payload.wrappedValue) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(payload.wrappedValue.label.isEmpty ? String(localized: "Formula") : payload.wrappedValue.label))
            .accessibilityValue(Text(failure ?? resultText))
        }
    }

    private var resultText: String {
        guard let result else { return "—" }
        return result.formatted(.number.precision(.fractionLength(0...2)))
    }

    @ViewBuilder
    private func expressionField(_ payload: Binding<FormulaPayload>) -> some View {
        if isEditingExpression {
            VStack(alignment: .leading, spacing: Layout.Space.tight) {
                TextField(
                    "Expression",
                    text: payload.expression,
                    prompt: Text("sum(subtotal)").foregroundStyle(theme.inkTertiary),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .versoText(.metadata)
                .foregroundStyle(theme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel(Text("Expression"))

                vocabulary

                Button("Done") { isEditingExpression = false }
                    .versoText(.chromeCaption)
            }
        } else {
            Button {
                isEditingExpression = true
            } label: {
                Text(payload.wrappedValue.expression.isEmpty
                     ? String(localized: "Tap to write an expression")
                     : payload.wrappedValue.expression)
                    .versoText(.metadata)
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Expression"))
            .accessibilityValue(Text(payload.wrappedValue.expression))
            .accessibilityHint(Text("Double tap to edit"))
        }
    }

    /// An expression language nobody can discover is a language nobody uses,
    /// so the names this note actually offers are listed where they're needed.
    private var vocabulary: some View {
        VStack(alignment: .leading, spacing: Layout.Space.hair) {
            ForEach(FormulaContextBuilder.vocabulary, id: \.name) { entry in
                HStack(spacing: Layout.Space.snug) {
                    Text(entry.name)
                        .versoText(.metadata)
                        .foregroundStyle(theme.accent)
                    Text(entry.summary)
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)
                }
            }
            Text("Functions: \(FormulaContextBuilder.functions.joined(separator: ", "))")
                .versoText(.chromeCaption)
                .foregroundStyle(theme.inkTertiary)
        }
        .padding(Layout.Space.snug)
        .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.tight))
    }

    private func evaluate(_ payload: FormulaPayload) {
        guard let note = block.note else {
            result = nil
            failure = nil
            return
        }
        guard !payload.expression.trimmingCharacters(in: .whitespaces).isEmpty else {
            result = nil
            failure = nil
            return
        }

        let context = FormulaContextBuilder.context(
            for: note,
            metrics: MetricSeriesStore(context: self.context)
        )

        do {
            result = try FormulaEvaluator.evaluate(payload.expression, context: context)
            failure = nil
        } catch {
            result = nil
            failure = error.localizedDescription
        }
    }
}
