import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion
    @Environment(HapticEngine.self) private var haptics
    @Environment(AppearanceStore.self) private var appearance
    @Environment(NavigationRequest.self) private var navigation

    @State private var path = NavigationPath()

    /// Sorted by recency only: `Bool` isn't `Comparable`, so pinning can't be a
    /// `SortDescriptor`. Pinned notes are lifted into their own section below.
    @Query(
        filter: #Predicate<Note> { !$0.isTrashed && !$0.isHidden },
        sort: [SortDescriptor(\Note.modifiedAt, order: .reverse)]
    )
    private var notes: [Note]

    /// Filtered in memory rather than by the query. Folder and tag membership
    /// are to-many relationships, which `#Predicate` cannot reach without a
    /// subquery per note — and these notes are already loaded to be drawn.
    private var visibleNotes: [Note] { notes.filter(filter.matches) }

    /// Built once per render rather than searched per row. A hit list and a
    /// note list are both O(n), and pairing them up by linear search made
    /// drawing results quadratic in the size of the library.
    private var notesByID: [UUID: Note] {
        Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var pinnedNotes: [Note] { visibleNotes.filter(\.isPinned) }
    private var unpinnedNotes: [Note] { visibleNotes.filter { !$0.isPinned } }
    private var unfiledCount: Int { notes.count(where: LibraryFilter.unfiled.matches) }

    @State private var isChoosingTemplate = false
    @State private var isCapturing = false
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    /// Built on the first search and kept, so the embedding model is loaded
    /// once per session rather than once per query.
    @State private var searchSource: SearchIndexSource?
    @State private var isShowingSettings = false
    @State private var isShowingTrash = false
    @State private var failure: String?
    @State private var filter: LibraryFilter = .all
    @State private var organising: Note?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !query.isEmpty {
                    searchResults
                } else if notes.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        LibraryFilterBar(filter: $filter, unfiledCount: unfiledCount)
                        if visibleNotes.isEmpty {
                            filteredEmptyState
                        } else {
                            noteList
                        }
                    }
                }
            }
            // The canvas, not the paper. Cards are the paper now, and a card
            // the same colour as what it sits on is not a card.
            .background(theme.canvas.ignoresSafeArea())
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
            // `initial: true` because the buffering above is otherwise wasted:
            // a widget tap or a Spotlight result on a *cold* launch sets the
            // request while this view is still being built, and `onChange`
            // alone does not fire for a value that was already there.
            .onChange(of: navigation.pending, initial: true) { _, _ in
                openPendingNote()
            }
            // And again when the query delivers. On a cold launch the request
            // is already set before the first render, so `initial: true` above
            // runs against an empty `notes` and finds nothing. The request is
            // deliberately left pending in that case rather than cleared, so
            // this second look is what actually opens it.
            .onChange(of: notes.count) { _, _ in
                openPendingNote()
            }
            // First launch opens on the gallery rather than on an empty list and
            // a plus, which describes nothing. Gated on the library actually
            // being empty as well as on the flag, so restoring from a backup —
            // where the notes arrive a moment after the view does — does not
            // greet someone with a gallery they have no use for.
            .task {
                guard !appearance.hasSeenGallery else { return }
                appearance.hasSeenGallery = true
                guard notes.isEmpty else { return }
                isChoosingTemplate = true
            }
            // Opening a template file launches the app, so this is always the
            // cold-launch case. The gallery is the confirmation: the import has
            // already happened, and it is sitting there under the user's own.
            .onChange(of: navigation.arrivedTemplate, initial: true) { _, arrival in
                guard arrival != nil else { return }
                isChoosingTemplate = true
                navigation.clearTemplateArrival()
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
            .sheet(item: $organising) { note in
                NoteOrganiseSheet(note: note)
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

    /// A `List` still, rather than a `ScrollView` of cards.
    ///
    /// The cards are rows with the separators and the row background taken
    /// away. Rebuilding this as a stack would have meant rebuilding swipe
    /// actions, drag-and-drop and the reordering VoiceOver already understands —
    /// a lot of working behaviour traded for a layout the row insets give up
    /// without argument.
    private var noteList: some View {
        List {
            if !pinnedNotes.isEmpty {
                Section {
                    ForEach(pinnedNotes) { row($0) }
                } header: {
                    SectionLabel(title: "Pinned")
                }
            }

            Section {
                ForEach(unpinnedNotes) { row($0) }
            } header: {
                SectionLabel(
                    title: pinnedNotes.isEmpty ? "All notes" : "Recent",
                    detail: "\(visibleNotes.count)"
                )
            }
        }
        .listStyle(.plain)
        .listRowSpacing(Layout.Space.snug)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, Layout.Space.regular, for: .scrollContent)
    }

    private func row(_ note: Note) -> some View {
        NavigationLink(value: note) {
            NoteRowView(note: note)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                trash(note)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                organising = note
            } label: {
                Label("Organise", systemImage: "folder")
            }
            Button {
                duplicate(note)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button {
                motion.run(.settle) { note.isPinned.toggle() }
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
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
            // Bound once here, deliberately. Read inside the `ForEach` closure
            // it would be rebuilt per row, which is the quadratic behaviour it
            // exists to remove, only with more allocation.
            let byID = notesByID
            List {
                ForEach(hits) { hit in
                    if let note = byID[hit.noteID] {
                        // The excerpt is why this note matched, so it belongs
                        // inside the card with it rather than stacked under a
                        // second one.
                        NavigationLink(value: note) {
                            NoteRowView(note: note, excerpt: hit.excerpt)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(Layout.Space.snug)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, Layout.Space.regular, for: .scrollContent)
        }
    }

    /// Searching happens on `SearchIndexSource`, not here.
    ///
    /// Building the entries means decoding every block of every note, and
    /// scoring them loads an embedding model — neither of which may run on the
    /// actor that has to keep the list at 60fps while someone is still typing.
    /// The source is held across searches so the model is loaded once.
    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }

        let source = searchSource ?? SearchIndexSource(modelContainer: context.container)
        searchSource = source

        let found = await source.search(trimmed)
        guard !Task.isCancelled else { return }
        hits = found
    }

    /// A filter that matches nothing. Different from an empty library, and
    /// worth saying differently: the notes exist, they are just not here.
    private var filteredEmptyState: some View {
        VStack(spacing: Layout.Space.cosy) {
            Text("Nothing here")
                .versoText(.title)
                .foregroundStyle(theme.ink)
            Button("Show all") {
                motion.run(.snap) { filter = .all }
            }
            .versoText(.chromeLabel)
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Layout.Space.loose)
    }

    /// An invitation, not an apology — and three words shorter than the
    /// apology was.
    private var emptyState: some View {
        VStack(spacing: Layout.Space.regular) {
            Image(systemName: "book.closed")
                .font(.system(size: Layout.Space.airy, weight: .light))
                .foregroundStyle(theme.inkTertiary)

            Text("Start a page")
                .versoText(.title)
                .foregroundStyle(theme.ink)

            Button {
                isChoosingTemplate = true
            } label: {
                Text("Choose a template")
                    .versoText(.chromeLabel)
                    .padding(.horizontal, Layout.Space.loose)
                    .padding(.vertical, Layout.Space.cosy)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.stock)
            .background(theme.accent, in: .rect(cornerRadius: Layout.Radius.capsule))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Layout.Space.loose)
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

    /// Opens whatever the outside world asked for, if it can be found yet.
    ///
    /// Leaves the request pending when the note is not in `notes` — it may
    /// simply not have loaded, and clearing here would lose a widget tap to a
    /// race with the query.
    private func openPendingNote() {
        guard let request = navigation.pending,
              let note = notes.first(where: { $0.id == request.noteID })
        else { return }
        path.append(note)
        navigation.clear()
    }

    /// Copies a note and opens the copy, because the reason to duplicate one is
    /// to start changing it.
    private func duplicate(_ note: Note) {
        let copy = note.duplicated(into: context, titleSuffix: String(localized: "Copy"))
        haptics.play(.checklistCheck)
        path.append(copy)
    }

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
