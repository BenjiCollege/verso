import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion
    @Environment(HapticEngine.self) private var haptics
    @Environment(NavigationRequest.self) private var navigation

    @State private var path = NavigationPath()

    /// Sorted by recency only: `Bool` isn't `Comparable`, so pinning can't be a
    /// `SortDescriptor`. Pinned notes are lifted into their own section below.
    @Query(
        filter: #Predicate<Note> { !$0.isTrashed && !$0.isHidden },
        sort: [SortDescriptor(\Note.modifiedAt, order: .reverse)]
    )
    private var notes: [Note]

    private var pinnedNotes: [Note] { notes.filter(\.isPinned) }
    private var unpinnedNotes: [Note] { notes.filter { !$0.isPinned } }

    @State private var isChoosingTemplate = false
    @State private var isCapturing = false
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var isShowingSettings = false
    @State private var isShowingTrash = false
    @State private var failure: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !query.isEmpty {
                    searchResults
                } else if notes.isEmpty {
                    emptyState
                } else {
                    noteList
                }
            }
            .background(theme.stock.ignoresSafeArea())
            // Registered once, here. The editor pushes with NavigationLink(value:)
            // rather than declaring its own destination, which would make the
            // view's type infinitely recursive the moment a note links to a note.
            .navigationDestination(for: Note.self) { note in
                NoteEditorView(note: note)
            }
            .navigationTitle("Verso")
            .toolbar { toolbarContent }
            .searchable(text: $query, prompt: Text("Search notes"))
            .task(id: query) {
                await runSearch()
            }
            // An intent, a widget tap, a Spotlight result or a Handoff can all
            // arrive before this view exists, so they are buffered and acted on
            // here rather than pushed from outside.
            .onChange(of: navigation.pending) { _, request in
                guard let request,
                      let note = notes.first(where: { $0.id == request.noteID })
                else { return }
                path.append(note)
                navigation.clear()
            }
            .sheet(isPresented: $isChoosingTemplate) {
                TemplateGalleryView(onSelect: createNote)
            }
            .sheet(isPresented: $isCapturing) {
                CaptureSheet { _ in }
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
            if !pinnedNotes.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedNotes) { row($0) }
                }
            }

            Section {
                ForEach(unpinnedNotes) { row($0) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ note: Note) -> some View {
        NavigationLink(value: note) {
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
                motion.run(.settle) { note.isPinned.toggle() }
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(theme.accent)
        }
        // Dragged out as Markdown, so a note dropped into Mail or Messages
        // arrives as something legible rather than as a link that only works
        // on this device. A locked note carries nothing.
        .draggable(NoteTransfer(note: note))
    }

    /// Semantic where the device supports it, lexical everywhere. Both paths
    /// exclude locked and hidden notes.
    @ViewBuilder
    private var searchResults: some View {
        if hits.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(hits) { hit in
                    if let note = notes.first(where: { $0.id == hit.noteID }) {
                        NavigationLink(value: note) {
                            VStack(alignment: .leading, spacing: Layout.Space.hair) {
                                NoteRowView(note: note)
                                if !hit.excerpt.isEmpty {
                                    Text(hit.excerpt)
                                        .versoText(.chromeCaption)
                                        .foregroundStyle(theme.inkSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .listRowBackground(theme.stock)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }

        let entries = notes.map { note in
            SemanticIndex.Entry(
                noteID: note.id,
                title: note.title,
                text: VaultPolicy.isEligibleForIndexing(note)
                    ? note.orderedBlocks.map { BlockRegistry.shared.plainText(for: $0) }.joined(separator: "\n")
                    : "",
                isLocked: !VaultPolicy.isEligibleForIndexing(note)
            )
        }
        hits = SemanticIndex().search(trimmed, in: entries)
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
            Menu {
                Button {
                    isChoosingTemplate = true
                } label: {
                    Label("From a Template", systemImage: "doc.on.doc")
                }
                Button {
                    isCapturing = true
                } label: {
                    Label("Paste or Dictate", systemImage: "sparkles")
                }
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            } primaryAction: {
                isChoosingTemplate = true
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
        haptics.play(.noteDeleted)
    }
}
