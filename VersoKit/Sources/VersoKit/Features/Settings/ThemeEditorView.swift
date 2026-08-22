import SwiftUI

/// Making a theme.
///
/// Seven colours chosen from nothing is a design job; adjusting two of an
/// existing seven is an afternoon's whim. So this always opens on a copy of a
/// working theme, and the preview above the pickers is the real page — the same
/// tokens, the same type, the same rules — rather than a row of swatches.
struct ThemeEditorView: View {
    @State var draft: Theme
    let onSave: (Theme) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var chromeTheme

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ThemePreview(theme: draft)
                        .listRowInsets(EdgeInsets())
                }

                Section("Name") {
                    TextField("Name", text: $draft.name)
                }

                Section {
                    Picker("Appearance", selection: $draft.appearance) {
                        Text("Light").tag(Theme.Appearance.light)
                        Text("Dark").tag(Theme.Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Which of Light and Dark Mode this theme belongs to. Verso uses it as the whole app's appearance while it's in use, so the toolbars match the paper.")
                }

                Section("Colours") {
                    swatch("Paper", \.stock)
                    swatch("Ink", \.ink)
                    swatch("Secondary ink", \.inkSecondary)
                    swatch("Accent", \.accent)
                    swatch("Rules", \.rule)
                    swatch("Fore-edge", \.edge)
                    swatch("Gilt", \.gilt)
                }

                Section {
                    HStack {
                        Text("Grain")
                        // The label is a sibling `Text`, which VoiceOver reads
                        // as its own element and does not attach to the
                        // control — so the slider announced itself as an
                        // unnamed percentage. Said explicitly here instead.
                        Slider(value: $draft.grain, in: 0...1, step: 0.05) {
                            Text("Grain")
                        }
                        .tint(draft.accent)
                        .accessibilityLabel(Text("Grain"))
                        .accessibilityValue(Text("\(Int(draft.grain * 100)) percent"))
                    }
                } footer: {
                    Text("Paper texture. Increase Contrast and Reduce Transparency flatten it to nothing whatever you set here.")
                }
            }
            .navigationTitle(draft.name.isEmpty ? String(localized: "New Theme") : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft.name = String(localized: "My Theme")
                        }
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private func swatch(
        _ label: LocalizedStringResource,
        _ key: WritableKeyPath<Theme.Palette, HexColor>
    ) -> some View {
        ColorPicker(
            selection: Binding(
                get: { draft.palette[keyPath: key].color },
                set: { draft.palette[keyPath: key] = HexColor($0) }
            ),
            supportsOpacity: false
        ) {
            Text(label)
        }
    }
}

/// A page, in the theme being made. Small, but real.
private struct ThemePreview: View {
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.snug) {
            Text("The quick brown fox")
                .versoText(.title)
                .foregroundStyle(theme.ink)

            Text("jumps over the lazy dog, and keeps going for long enough to show a second line of body copy.")
                .versoText(.body)
                .foregroundStyle(theme.ink)

            Rectangle()
                .fill(theme.rule)
                .frame(height: Layout.hairline)

            HStack(spacing: Layout.Space.snug) {
                Text("Secondary")
                    .versoText(.footnote)
                    .foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(Layout.Space.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A specimen, not prose. Read verbatim it is a pangram and a line of
        // filler, which tells a VoiceOver user nothing about the theme — so it
        // is one element that says what it is for.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview of this theme"))
        .background(theme.stock)
        .overlay(alignment: .leading) {
            // The fore-edge, which is the one token you cannot judge from a
            // swatch — it is only ever seen as a thin strip.
            Rectangle()
                .fill(theme.edge)
                .frame(width: Layout.foreEdgeWidth)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(theme.gilt)
                        .frame(width: Layout.hairline)
                }
        }
        .clipShape(.rect(cornerRadius: Layout.Radius.regular))
        .padding(Layout.Space.regular)
        // The preview is a page in *its* appearance, not the app's, so a dark
        // theme previewed from a light app still reads as itself.
        .environment(\.colorScheme, theme.colorScheme)
    }
}
