import SwiftData
import SwiftUI

/// Recently Deleted. Small, but it exists in Phase 1 because a soft delete the
/// user cannot reverse is worse than no soft delete at all.
struct TrashView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @Query(
        filter: #Predicate<Note> { $0.isTrashed },
        sort: [SortDescriptor(\Note.trashedAt, order: .reverse)]
    )
    private var notes: [Note]

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "Nothing deleted",
                        systemImage: "trash",
                        description: Text("Deleted notes appear here.")
                    )
                } else {
                    list
                }
            }
            .background(theme.stock.ignoresSafeArea())
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Empty", role: .destructive) { emptyTrash() }
                        .disabled(notes.isEmpty)
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(notes) { note in
                NoteRowView(note: note)
                    .listRowBackground(theme.stock)
                    .swipeActions(edge: .leading) {
                        Button {
                            restore(note)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(theme.accent)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            context.delete(note)
                        } label: {
                            Label("Delete Now", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func restore(_ note: Note) {
        note.isTrashed = false
        note.trashedAt = nil
    }

    private func emptyTrash() {
        for note in notes {
            context.delete(note)
        }
    }
}
