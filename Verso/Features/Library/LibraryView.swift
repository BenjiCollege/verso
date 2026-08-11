import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    @Query(
        filter: #Predicate<Note> { !$0.isTrashed && !$0.isHidden },
        sort: [
            SortDescriptor(\Note.isPinned, order: .reverse),
            SortDescriptor(\Note.modifiedAt, order: .reverse),
        ]
    )
    private var notes: [Note]

    @State private var isChoosingTemplate = false
    @State private var isShowingSettings = false
    @State private var isShowingTrash = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    emptyState
                } else {
                    noteList
                }
            }
            .background(theme.stock.ignoresSafeArea())
            .navigationTitle("Verso")
            .toolbar { toolbarContent }
            .sheet(isPresented: $isChoosingTemplate) {
                NewNoteSheet(onSelect: createNote)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingTrash) {
                TrashView()
            }
            .alert(
                "Couldn't create the note",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) { failure = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    // MARK: - Content

    private var noteList: some View {
        List {
            ForEach(notes) { note in
                NavigationLink {
                    NoteEditorView(note: note)
                } label: {
                    NoteRowView(note: note)
                }
                .listRowBackground(theme.stock)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        trash(note)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        motion.run(.settle) {
                            note.isPinned.toggle()
                        }
                    } label: {
                        Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(theme.accent)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No notes yet", systemImage: "book.closed")
        } description: {
            Text("Start from a blank page or pick a template.")
        } actions: {
            Button("New Note") { isChoosingTemplate = true }
                .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isChoosingTemplate = true
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {
                    isShowingTrash = true
                } label: {
                    Label("Recently Deleted", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func createNote(from template: Template) {
        do {
            try TemplateInstantiator.makeNote(from: template, in: context)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Soft delete. Notes go to Recently Deleted rather than disappearing,
    /// because a swipe is easy to do by accident and sync makes it permanent
    /// on every device at once.
    private func trash(_ note: Note) {
        motion.run(.settle) {
            note.isTrashed = true
            note.trashedAt = Date()
        }
    }
}
