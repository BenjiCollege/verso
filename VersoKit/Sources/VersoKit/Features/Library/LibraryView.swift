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

    /// Which layout to draw.
    ///
    /// The app has shipped `TARGETED_DEVICE_FAMILY: "1,2"` from the start with
    /// no size-class awareness anywhere, so an iPad got the phone's screen
    /// stretched: one column, folders hidden behind a horizontal swipe, and a
    /// note pushed over the list it came from. For an app whose whole metaphor
    /// is a page, that is the device it should be best on.
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The note in the detail column. Only the wide layout uses it — the
    /// compact one pushes onto `path`, which is a different model and has to
    /// stay that way: a `NavigationSplitView` selection and a `NavigationStack`
    /// path disagree about what "back" means.
    @State private var selectedNote: Note?

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
    /// Whether a search is in flight.
    ///
    /// Without this the view had two states, and the empty one doubled as the
    /// loading one: the first keystroke of the first search asserted "No
    /// Results" for the 200ms debounce *plus* a cold search that loads an
    /// embedding model and decodes every block of every note. Telling someone
    /// their query found nothing, before looking, is the worst available answer.
    @State private var isSearching = false
    /// Built on the first search and kept, so the embedding model is loaded
    /// once per session rather than once per query.
    @State private var searchSource: SearchIndexSource?
    @State private var isShowingSettings = false
    @State private var isShowingTrash = false
    @State private var failure: String?
    @State private var filter: LibraryFilter = .all
    @State private var organising: Note?

    var body: some View {
        Group {
            if sizeClass == .regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        // Everything below is layout-independent: sheets, alerts and the
        // buffered requests from widgets, Spotlight and Handoff. Attached once
        // to the `Group` so the two layouts cannot drift apart on any of it.
        .sheet(isPresented: $isChoosingTemplate) {
            TemplateGalleryView(onSelect: createNote)
        }
        .sheet(isPresented: $isCapturing) {
            CaptureSheet { note in
                haptics.play(.checklistCheck)
                open(note)
            }
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
        .onChange(of: navigation.pending, initial: true) { _, _ in
            openPendingNote()
        }
        .onChange(of: notes.count) { _, _ in
            openPendingNote()
        }
        .onChange(of: navigation.pendingCapture, initial: true) { _, requested in
            guard requested != nil else { return }
            isCapturing = true
            navigation.clearCapture()
        }
        .onChange(of: navigation.arrivedTemplate, initial: true) { _, arrival in
            guard arrival != nil else { return }
            isChoosingTemplate = true
            navigation.clearTemplateArrival()
        }
        .task {
            guard !appearance.hasSeenGallery else { return }
            guard navigation.pendingCapture == nil, navigation.pending == nil else { return }
            appearance.hasSeenGallery = true
            guard notes.isEmpty else { return }
            isChoosingTemplate = true
        }
    }

    // MARK: - Wide

    /// Sidebar, list, page.
    private var splitLayout: some View {
        NavigationSplitView {
            LibrarySidebar(
                filter: $filter,
                unfiledCount: unfiledCount,
                onSettings: { isShowingSettings = true },
                onTrash: { isShowingTrash = true }
            )
        } content: {
            listColumn
                // The canvas, same as the compact layout. Without it the column
                // renders on the system's default list background — white next
                // to a themed sidebar and a themed page, which is the one place
                // in the app where two surfaces disagree.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.canvas.ignoresSafeArea())
                .navigationTitle(filterTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { newNoteButton }
                .searchable(text: $query, prompt: Text("Search notes"))
                .task(id: query) { await runSearch() }
        } detail: {
            if let selectedNote {
                NoteEditorView(note: selectedNote)
                    // Rebuilds the editor when the selection changes. Without
                    // it SwiftUI reuses the view and the previous note's
                    // scroll offset, fore-edge and editing session survive into
                    // the next one.
                    .id(selectedNote.id)
            } else {
                noNoteSelected
            }
        }
    }

    /// The detail column with nothing in it. A blank half-screen reads as a
    /// bug; this reads as a choice.
    private var noNoteSelected: some View {
        VStack(spacing: Layout.Space.regular) {
            Image(systemName: "book.closed")
                .font(.system(size: Layout.Space.airy, weight: .light))
                .foregroundStyle(theme.inkTertiary)
            Text("Choose a page")
                .versoText(.title)
                .foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas.ignoresSafeArea())
    }

    private var filterTitle: String {
        switch filter {
        case .all: String(localized: "All Notes")
        case .unfiled: String(localized: "Unfiled")
        case .folder, .tag: String(localized: "Notes")
        }
    }

    /// Shared by both layouts — the list itself never differed, only what is
    /// around it.
    @ViewBuilder
    private var listColumn: some View {
        if !query.isEmpty {
            searchResults
        } else if notes.isEmpty {
            emptyState
        } else if visibleNotes.isEmpty {
            filteredEmptyState
        } else {
            noteList
        }
    }

    // MARK: - Compact

    private var stackLayout: some View {
        NavigationStack(path: $path) {
            Group {
                if !query.isEmpty || notes.isEmpty {
                    listColumn
                } else {
                    VStack(spacing: 0) {
                        LibraryFilterBar(filter: $filter, unfiledCount: unfiledCount)
                        listColumn
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
        // A `Button`, not a `NavigationLink`.
        //
        // `NavigationLink(value:)` drives a `NavigationStack`'s path, which is
        // the wrong thing entirely in the wide layout: it would push the note
        // *inside* the list column rather than showing it in the detail one.
        // Routing through `open(_:)` means one row definition behaves correctly
        // in both, and the selected note is highlighted rather than lost.
        Button {
            open(note)
        } label: {
            HStack(spacing: Layout.Space.snug) {
                NoteRowView(note: note)
                // The chevron came free with `NavigationLink` and has to be
                // drawn now — but only where tapping actually goes somewhere
                // else. In the wide layout the note appears beside the list,
                // so an arrow pointing off the edge of the column would be
                // describing navigation that does not happen.
                if sizeClass != .regular {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selectedNote?.id == note.id && sizeClass == .regular
                ? theme.accent.opacity(0.12)
                : Color.clear
        )
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
        if hits.isEmpty && isSearching {
            // Searching, nothing to show yet.
            ProgressView()
                .controlSize(.large)
                .tint(theme.inkTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Searching"))
        } else if hits.isEmpty {
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
                        Button {
                            open(note)
                        } label: {
                            NoteRowView(note: note, excerpt: hit.excerpt)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
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
            isSearching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }

        // Only after the debounce, so a fast typist never sees a spinner flash
        // between keystrokes — by then the previous task has been cancelled and
        // this one is genuinely about to do the work.
        isSearching = true
        defer { isSearching = false }

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

    /// The wide layout puts New Note on the list column and the rest in the
    /// sidebar, so the two toolbars are not the same set.
    @ToolbarContentBuilder
    private var newNoteButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("From a Template", systemImage: "doc.on.doc") {
                    isChoosingTemplate = true
                }
                Button("Paste or Dictate", systemImage: "sparkles") {
                    isCapturing = true
                }
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            } primaryAction: {
                isChoosingTemplate = true
            }
            // The app had no keyboard shortcuts at all — `keyboardShortcut`
            // appeared zero times in twenty-three thousand lines — which on an
            // iPad with a Magic Keyboard is the difference between a writing
            // app and a demo. ⌘N is the one every app on the platform has.
            .keyboardShortcut("n", modifiers: .command)
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
            .keyboardShortcut("n", modifiers: .command)
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
    /// Opens a note in whichever layout is on screen.
    ///
    /// The two navigation models are genuinely different — the stack pushes and
    /// the split view selects — and every caller wants "show me this note"
    /// rather than to know which. Routing them all through here is what stops
    /// a feature working on the phone and doing nothing on iPad.
    private func open(_ note: Note) {
        if sizeClass == .regular {
            selectedNote = note
        } else {
            path.append(note)
        }
    }

    private func openPendingNote() {
        guard let request = navigation.pending,
              let note = notes.first(where: { $0.id == request.noteID })
        else { return }
        open(note)
        navigation.clear()
    }

    /// Copies a note and opens the copy, because the reason to duplicate one is
    /// to start changing it.
    private func duplicate(_ note: Note) {
        let copy = note.duplicated(into: context, titleSuffix: String(localized: "Copy"))
        haptics.play(.checklistCheck)
        open(copy)
    }

    /// Makes the note **and opens it**.
    ///
    /// The note was already being created correctly and then thrown away —
    /// `makeNote` is `@discardableResult` and the result was discarded, so
    /// picking a template dropped you back on the library to go and find the
    /// thing you had just asked for. On first launch, where the gallery opens
    /// unprompted, that meant the app's opening move was to hand you a list.
    ///
    /// Picking a template is a statement of intent to write. `duplicate(_:)`
    /// twenty lines above already gets this right, for the same reason.
    ///
    /// The date needs no special handling: `makeNote(date:)` defaults to `Date()`
    /// at the moment of the call, `Note.init` stamps `createdAt` and
    /// `modifiedAt` from it, and `{date}`/`{time}`/`{weekday}` in a template's
    /// `titleFormat` resolve against the same value — so the note, its title and
    /// its position in the recency sort all agree on now.
    private func createNote(from template: Template) {
        do {
            let note = try TemplateInstantiator.makeNote(from: template, in: context)
            haptics.play(.checklistCheck)
            open(note)
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
