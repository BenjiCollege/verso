import SwiftUI

/// Picks an entry from a catalog — the exercise library, or any other one a
/// template names. Choosing sets the metric's label, its series and, if the
/// entry declares one, its unit.
struct CatalogPickerSheet: View {
    let catalog: Catalog
    let onSelect: (Catalog.Entry) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var query = ""
    @State private var selectedTag: String?

    private var entries: [Catalog.Entry] {
        catalog.entries.filter { entry in
            entry.matches(query) && (selectedTag == nil || entry.tags.contains(selectedTag!))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tagFilter

                List(entries) { entry in
                    Button {
                        onSelect(entry)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: Layout.Space.hair) {
                            Text(entry.name)
                                .versoText(.chromeBody)
                                .foregroundStyle(theme.ink)

                            if let notes = entry.notes {
                                Text(notes)
                                    .versoText(.chromeCaption)
                                    .foregroundStyle(theme.inkSecondary)
                            }

                            if !entry.tags.isEmpty {
                                Text(entry.tags.joined(separator: " · "))
                                    .versoText(.metadata)
                                    .foregroundStyle(theme.inkTertiary)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
                .listStyle(.plain)
                .overlay {
                    if entries.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: Text("Search \(catalog.name.lowercased())"))
            .navigationTitle(catalog.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Facets come from the catalog's own tags. The engine has no idea these
    /// are muscle groups.
    private var tagFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Layout.Space.snug) {
                chip(title: String(localized: "All"), tag: nil)
                ForEach(catalog.tagValues, id: \.self) { tag in
                    chip(title: tag.localizedCapitalized, tag: tag)
                }
            }
            .padding(.horizontal, Layout.Space.regular)
            .padding(.vertical, Layout.Space.snug)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(title: String, tag: String?) -> some View {
        let isSelected = selectedTag == tag

        return Button {
            selectedTag = tag
        } label: {
            Text(title)
                .versoText(.metadata)
                .foregroundStyle(isSelected ? theme.stock : theme.ink)
                .padding(.horizontal, Layout.Space.cosy)
                .padding(.vertical, Layout.Space.tight)
                .background(
                    isSelected ? theme.accent : theme.inset,
                    in: .rect(cornerRadius: Layout.Radius.capsule)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
