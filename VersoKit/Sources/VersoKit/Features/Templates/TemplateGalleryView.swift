import SwiftUI
import UniformTypeIdentifiers

/// The template gallery.
///
/// Bundled templates and the user's own are shown side by side and behave
/// identically, because they are the same thing: a JSON file. Adding one to the
/// bundle needs no change here, and neither does adding a block type.
struct TemplateGalleryView: View {
    let onSelect: (Template) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(UserTemplateStore.self) private var userStore

    @State private var query = ""
    @State private var isImporting = false
    @State private var renamingTemplate: Template?
    @State private var newName = ""

    private let bundled = TemplateCatalog.shared

    var body: some View {
        NavigationStack {
            List {
                if !userSection.isEmpty {
                    Section("Yours") {
                        ForEach(userSection) { template in
                            row(template)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        userStore.delete(id: template.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu { userTemplateMenu(template) }
                        }
                    }
                }

                ForEach(sections, id: \.key) { section in
                    Section(section.title) {
                        ForEach(section.templates) { row($0) }
                    }
                }

                if sections.isEmpty && userSection.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: Text("Search templates"))
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.versoTemplate, .json]
            ) { result in
                guard case .success(let url) = result else { return }
                userStore.importTemplate(from: url)
            }
            .alert("Rename template", isPresented: renamingBinding) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renamingTemplate = nil }
                Button("Rename") {
                    if let template = renamingTemplate, !newName.isEmpty {
                        userStore.rename(id: template.id, to: newName)
                    }
                    renamingTemplate = nil
                }
            }
        }
    }

    // MARK: - Rows

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
                            .lineLimit(2)
                    }

                    Text("\(template.blocks.count) blocks")
                        .versoText(.metadata)
                        .foregroundStyle(theme.inkTertiary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Creates a note from this template"))
    }

    @ViewBuilder
    private func userTemplateMenu(_ template: Template) -> some View {
        Button {
            renamingTemplate = template
            newName = template.name
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        // Sharing a template is a file changing hands. There is no server here
        // and never will be.
        if let url = try? userStore.exportFile(for: template) {
            ShareLink(item: url) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }

        Button(role: .destructive) {
            userStore.delete(id: template.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Grouping

    private struct GallerySection {
        let key: String
        let title: String
        let templates: [Template]
    }

    private func matches(_ template: Template) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        func contains(_ text: String?) -> Bool {
            guard let text else { return false }
            return text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
        }
        return contains(template.name) || contains(template.summary) || contains(template.category)
    }

    private var userSection: [Template] {
        userStore.templates.filter(matches)
    }

    /// Category keys are opaque strings from JSON. They are title-cased for
    /// display and nothing branches on their value, so a template file can
    /// invent a new category and it will simply appear.
    private var sections: [GallerySection] {
        let supported = bundled.supported.filter(matches)
        var seen = Set<String>()
        let categories = supported.compactMap(\.category).filter { seen.insert($0).inserted }

        var result = categories.map { category in
            GallerySection(
                key: category,
                title: category.replacingOccurrences(of: "-", with: " ").localizedCapitalized,
                templates: supported.filter { $0.category == category }
            )
        }

        let uncategorised = supported.filter { $0.category == nil }
        if !uncategorised.isEmpty {
            result.append(GallerySection(key: "__other", title: String(localized: "Other"), templates: uncategorised))
        }
        return result
    }

    private var renamingBinding: Binding<Bool> {
        Binding(
            get: { renamingTemplate != nil },
            set: { if !$0 { renamingTemplate = nil } }
        )
    }
}
