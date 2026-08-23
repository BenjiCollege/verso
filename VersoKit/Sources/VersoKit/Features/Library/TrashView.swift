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
            .background(theme.canvas.ignoresSafeArea())
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            // Two dialogs, because this screen holds the only two operations in
            // the app that destroy a note with nothing behind them. Everywhere
            // else a delete is a soft delete or an undoable block edit; here it
            // is the end. The file's own doc comment argues a soft delete the
            // user cannot reverse is worse than none — that applies to the
            // emptying as much as to the trashing.
            // `inflect: true` so one note is not "1 notes". Automatic grammar
            // agreement covers English and five other languages; hand-writing a
            // plural here would be correct in exactly one of them.
            // No count in the title, deliberately. `^[...](inflect: true)`
            // resolves on the button, which binds to `LocalizedStringKey`, but
            // a dialog title with a value interpolated into it binds to the
            // plain-String overload and renders the markup verbatim — verified
            // on device, including via `String(localized:)`. The button carries
            // the exact number, so the title does not need to.
            .confirmationDialog(
                "Delete everything in Recently Deleted?",
                isPresented: $isConfirmingEmpty,
                titleVisibility: .visible
            ) {
                Button("Delete ^[\(notes.count) note](inflect: true)", role: .destructive, action: emptyTrash)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone, on this device or any other.")
            }
            .confirmationDialog(
                "Delete this note permanently?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { note in
                Button("Delete Note", role: .destructive) { deletePermanently(note) }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { note in
                Text(note.title.isEmpty
                     ? String(localized: "This cannot be undone.")
                     : String(localized: "“\(note.title)” cannot be recovered."))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    // The count is in the label, so the stake is visible before
                    // the tap rather than only in the dialog after it.
                    Button("Empty (\(notes.count))", role: .destructive) {
                        isConfirmingEmpty = true
                    }
                    .disabled(notes.isEmpty)
                }
            }
        }
    }

    /// The note the user has asked to destroy, pending confirmation.
    @State private var deleting: Note?
    @State private var isConfirmingEmpty = false

    private var list: some View {
        List {
            ForEach(notes) { note in
                NoteRowView(note: note)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .leading) {
                        Button {
                            restore(note)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(theme.accent)
                    }
                    // `allowsFullSwipe: false`, because the default lets a fast
                    // swipe destroy a note permanently without the button ever
                    // being seen. This is the one delete in the app with no
                    // second copy behind it; it has to be deliberate.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleting = note
                        } label: {
                            Label("Delete Now", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(Layout.Space.snug)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, Layout.Space.regular, for: .scrollContent)
        .background(theme.canvas.ignoresSafeArea())
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

    private func deletePermanently(_ note: Note) {
        context.delete(note)
    }
}
