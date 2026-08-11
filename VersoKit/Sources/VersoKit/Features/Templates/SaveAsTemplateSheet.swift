import SwiftUI

/// Saving a note as a template.
///
/// The only choice that matters is whether to keep what is written in it. The
/// default is not to: a template is a shape, and a shape you can hand to
/// somebody else without handing over last week's shopping.
struct SaveAsTemplateSheet: View {
    let note: Note

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(UserTemplateStore.self) private var store

    @State private var name: String
    @State private var summary = ""
    @State private var category = ""
    @State private var keepContents = false
    @State private var failure: String?

    init(note: Note) {
        self.note = note
        _name = State(initialValue: TemplateAuthoring.suggestedName(for: note))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Summary", text: $summary, axis: .vertical)
                    TextField("Category", text: $category)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("A category groups this with others in the gallery. Anything you like.")
                }

                Section {
                    Toggle("Keep what's written in it", isOn: $keepContents)
                } footer: {
                    Text(keepContents
                         ? "The template will include everything currently in the note."
                         : "The structure is kept — headings, groups, columns, which fields are shown — and the contents are cleared.")
                }

                Section {
                    LabeledContent("Blocks") {
                        Text("\(note.orderedBlocks.count)")
                            .foregroundStyle(theme.inkSecondary)
                    }
                }

                if let failure {
                    Section {
                        Text(failure).foregroundStyle(theme.accent)
                    }
                }
            }
            .navigationTitle("Save as Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            let template = try TemplateAuthoring.makeTemplate(
                from: note,
                name: name.trimmingCharacters(in: .whitespaces),
                summary: summary.trimmingCharacters(in: .whitespaces),
                category: category.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil
                    : category.trimmingCharacters(in: .whitespaces).lowercased(),
                keepContents: keepContents
            )
            guard store.save(template) else {
                failure = store.lastError ?? String(localized: "Couldn't save the template.")
                return
            }
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
