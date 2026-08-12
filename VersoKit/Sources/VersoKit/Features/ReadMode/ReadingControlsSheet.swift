import SwiftUI

/// Size, leading, margin and face — adjusted where you are reading.
///
/// In Read Mode rather than only in Settings, because these are the settings you
/// discover you want *while* reading, and a trip to Settings to widen a margin
/// is a trip you take once and then stop taking.
struct ReadingControlsSheet: View {
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var appearance = appearance

        NavigationStack {
            Form {
                Section {
                    Picker("Typeface", selection: $appearance.typeface) {
                        ForEach(ContentTypeface.allCases) { face in
                            Text(face.displayName).tag(face)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(appearance.typeface.summary)
                }

                Section("Size") {
                    LabelledSlider(
                        value: $appearance.textScale,
                        range: ReadingPreferences.textScaleRange,
                        minimumIcon: "textformat.size.smaller",
                        maximumIcon: "textformat.size.larger",
                        label: "Text size"
                    )
                    LabelledSlider(
                        value: $appearance.lineSpacingScale,
                        range: ReadingPreferences.lineSpacingRange,
                        minimumIcon: "arrow.up.and.down.compress",
                        maximumIcon: "arrow.up.and.down",
                        label: "Line spacing"
                    )
                    LabelledSlider(
                        value: $appearance.marginScale,
                        range: ReadingPreferences.marginRange,
                        minimumIcon: "arrow.left.and.right",
                        maximumIcon: "arrow.right.and.line.vertical.and.arrow.left",
                        label: "Margins"
                    )
                }

                Section {
                    Button("Reset to defaults") {
                        appearance.resetReading()
                    }
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A slider between two icons, with the value announced rather than drawn —
/// a number beside a slider is noise, but VoiceOver needs one.
private struct LabelledSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let minimumIcon: String
    let maximumIcon: String
    let label: LocalizedStringResource

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Layout.Space.cosy) {
            Image(systemName: minimumIcon)
                .foregroundStyle(theme.inkSecondary)
                .accessibilityHidden(true)

            Slider(value: $value, in: range, step: 0.05)
                .tint(theme.accent)

            Image(systemName: maximumIcon)
                .foregroundStyle(theme.inkSecondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value.formatted(.percent.precision(.fractionLength(0)))))
    }
}
