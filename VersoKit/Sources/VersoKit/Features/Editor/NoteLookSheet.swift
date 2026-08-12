import SwiftData
import SwiftUI

/// One note's own theme, paper and reveal.
///
/// Notes could already carry these — templates set them — but nothing let you
/// change them afterwards, so a page's look was decided once, by whoever wrote
/// the template, and never again.
///
/// "Same as the app" is a real choice rather than the absence of one: it keeps
/// `themeID` nil, so the note follows the app when the app changes. Picking a
/// theme here pins this note to it for good.
struct NoteLookSheet: View {
    @Bindable var note: Note

    @Environment(\.themeCatalog) private var catalog
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    row(title: "Same as the app", isSelected: note.themeID == nil) {
                        note.themeID = nil
                    }
                    ForEach(catalog.themes) { candidate in
                        row(title: candidate.name, isSelected: note.themeID == candidate.id) {
                            note.themeID = candidate.id
                        } leading: {
                            ThemeSwatch(theme: candidate)
                        }
                    }
                }

                Section("Paper") {
                    row(title: "Same as the app", isSelected: note.stockID == nil) {
                        note.stockID = nil
                    }
                    ForEach(catalog.stocks) { candidate in
                        row(title: candidate.name, isSelected: note.stockID == candidate.id) {
                            note.stockID = candidate.id
                        }
                    }
                }

                Section {
                    row(title: "Same as the app", isSelected: note.revealStyleID == nil) {
                        note.revealStyleID = nil
                    }
                    ForEach(RevealStyle.allCases, id: \.self) { style in
                        row(title: String(localized: style.displayName), isSelected: note.revealStyleID == style.rawValue) {
                            note.revealStyleID = style.rawValue
                        }
                    }
                } header: {
                    Text("Reveal")
                } footer: {
                    Text("How the note arrives in Read Mode. Reduce Motion flattens every one of these.")
                }
            }
            .navigationTitle("Page Look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        note.touch()
                        dismiss()
                    }
                }
            }
        }
    }

    private func row(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder leading: () -> some View = { EmptyView() }
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Layout.Space.cosy) {
                leading()
                Text(title)
                    .versoText(.chromeBody)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
