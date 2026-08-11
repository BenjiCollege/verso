import SwiftUI

/// Template chooser. Reads `TemplateCatalog.supported`, so a template added as
/// a JSON file appears here with no change to this file.
struct NewNoteSheet: View {
    let onSelect: (Template) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    private let catalog = TemplateCatalog.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.key) { section in
                    Section(section.title) {
                        ForEach(section.templates) { template in
                            row(template)
                        }
                    }
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ template: Template) -> some View {
        Button {
            onSelect(template)
            dismiss()
        } label: {
            HStack(spacing: Layout.Space.cosy) {
                Image(systemName: template.systemImage)
                    .foregroundStyle(theme.accent)
                    .frame(width: Layout.Space.loose)

                VStack(alignment: .leading, spacing: Layout.Space.hair) {
                    Text(template.name)
                        .versoText(.chromeBody)
                        .foregroundStyle(theme.ink)

                    if let summary = template.summary {
                        Text(summary)
                            .versoText(.chromeCaption)
                            .foregroundStyle(theme.inkSecondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Creates a note from this template"))
    }

    // MARK: - Grouping

    private struct TemplateSection {
        let key: String
        let title: String
        let templates: [Template]
    }

    /// Category keys are opaque to the engine; they are title-cased for display
    /// and nothing branches on their value.
    private var sections: [TemplateSection] {
        var result = catalog.categories.map { category in
            TemplateSection(
                key: category,
                title: category.replacingOccurrences(of: "-", with: " ").localizedCapitalized,
                templates: catalog.templates(in: category)
            )
        }

        let uncategorised = catalog.supported.filter { $0.category == nil }
        if !uncategorised.isEmpty {
            result.append(TemplateSection(key: "__other", title: String(localized: "Other"), templates: uncategorised))
        }
        return result
    }
}
