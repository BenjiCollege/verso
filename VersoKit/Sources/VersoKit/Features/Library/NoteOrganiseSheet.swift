import SwiftData
import SwiftUI

/// Where a note is filed, and what it is about.
///
/// One sheet for both, because they are the same decision made twice: a folder
/// is the one place a note lives, tags are the several things it is about. Two
/// separate screens would make that distinction harder to see rather than
/// easier.
struct NoteOrganiseSheet: View {
    @Bindable var note: Note

    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\Folder.position)]) private var folders: [Folder]
    @Query(sort: [SortDescriptor(\Tag.name)]) private var allTags: [Tag]

    @State private var newFolderName = ""
    @State private var newTagName = ""

    private var noteTags: [Tag] {
        (note.tags ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder") {
                    folderRow(name: String(localized: "None"), icon: "tray", isSelected: note.folder == nil) {
                        note.folder = nil
                    }
                    ForEach(folders) { folder in
                        folderRow(name: folder.name, icon: folder.icon, isSelected: note.folder?.id == folder.id) {
                            note.folder = folder
                        }
                    }

                    HStack {
                        TextField("New folder", text: $newFolderName)
                            .onSubmit(addFolder)
                        Button("Add", action: addFolder)
                            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Tags") {
                    if !noteTags.isEmpty {
                        // Wrapping, not scrolling: a row of tags you have to
                        // swipe through hides the ones you have.
                        FlowLayout(spacing: Layout.Space.snug) {
                            ForEach(noteTags) { tag in
                                Button {
                                    remove(tag)
                                } label: {
                                    VersoPill(title: tag.name, systemImage: "xmark")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Remove \(tag.name)"))
                            }
                        }
                    }

                    HStack {
                        TextField("New tag", text: $newTagName)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addTag)
                        Button("Add", action: addTag)
                            .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    let unused = allTags.filter { candidate in
                        !noteTags.contains { $0.id == candidate.id }
                    }
                    if !unused.isEmpty {
                        FlowLayout(spacing: Layout.Space.snug) {
                            ForEach(unused) { tag in
                                Button {
                                    attach(tag)
                                } label: {
                                    VersoPill(title: tag.name, systemImage: "plus")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Add \(tag.name)"))
                            }
                        }
                    }
                }
            }
            .listRowBackground(theme.card)
            .scrollContentBackground(.hidden)
            .background(theme.canvas.ignoresSafeArea())
            .navigationTitle("Organise")
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

    private func folderRow(
        name: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Layout.Space.cosy) {
                Image(systemName: icon)
                    .foregroundStyle(theme.accent)
                    .frame(width: Layout.Space.loose)
                Text(name)
                    .versoText(.chromeBody)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Actions

    private func addFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let folder = try? Folder.findOrCreate(named: name, in: context) else { return }
        note.folder = folder
        newFolderName = ""
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let tag = try? Tag.findOrCreate(named: name, in: context) else { return }
        attach(tag)
        newTagName = ""
    }

    private func attach(_ tag: Tag) {
        guard !(note.tags ?? []).contains(where: { $0.id == tag.id }) else { return }
        note.tags = (note.tags ?? []) + [tag]
    }

    private func remove(_ tag: Tag) {
        note.tags = (note.tags ?? []).filter { $0.id != tag.id }
    }
}
