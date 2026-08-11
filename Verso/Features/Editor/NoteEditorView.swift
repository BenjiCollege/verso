import SwiftData
import SwiftUI

/// The page.
///
/// A `ScrollView` rather than a `List`, because typewriter scroll needs an
/// exact content offset and a `List` will not surrender one. Reordering moved
/// to `BlockReorderSheet` in exchange, which keeps drag-and-drop and VoiceOver
/// on a control built for it.
struct NoteEditorView: View {
    @Bindable var note: Note

    static let pageCoordinateSpace = "verso.page"

    @Environment(\.modelContext) private var context
    @Environment(\.themeCatalog) private var catalog
    @Environment(\.theme) private var appTheme
    @Environment(\.stock) private var appStock
    @Environment(\.motion) private var motion
    @Environment(AppearanceStore.self) private var appearance
    @Environment(LinkIndex.self) private var linkIndex

    @State private var session = TextEditingSession()
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollGeometry: ScrollGeometry?
    @State private var isReordering = false
    @State private var isFocusMode = false
    @State private var isCaretSuppressed = false

    private var theme: Theme { catalog.theme(id: note.themeID) ?? appTheme }
    private var stock: Stock { catalog.stock(id: note.stockID) ?? appStock }

    private var scroller: TypewriterScroller {
        TypewriterScroller(isEnabled: appearance.isTypewriterEnabled)
    }

    /// Focus Mode hides the chrome as well as dimming the page, so there is
    /// nothing on screen but the sentence being written.
    private var isChromeHidden: Bool { isFocusMode && session.isEditing }

    var body: some View {
        ZStack {
            theme.stock.ignoresSafeArea()
            page
        }
        .versoTheme(theme, stock: stock, pinnedColorScheme: note.themeID == nil ? nil : theme.colorScheme)
        .environment(\.textEditingSession, session)
        .environment(\.editorFocusMode, isFocusMode)
        .environment(\.caretSuppressed, isCaretSuppressed)
        .navigationTitle(note.title.isEmpty ? String(localized: "Untitled") : note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isChromeHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) { keyboardAccessories }
        .sheet(isPresented: $isReordering) {
            BlockReorderSheet(note: note)
        }
        .onChange(of: session.caretRectInPage) { _, caret in
            followCaret(to: caret)
        }
        .onDisappear {
            Task { await linkIndex.noteDidChange(note.id) }
        }
    }

    // MARK: - Page

    private var page: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.Space.snug) {
                titleField

                ForEach(note.orderedBlocks) { block in
                    BlockRenderer(block: block)
                        .opacity(dimming(for: block))
                        .animation(motion.animation(.settle), value: isChromeHidden)
                        .animation(motion.animation(.settle), value: session.activeBlockID)
                }

                BacklinksView(noteID: note.id)

                Color.clear
                    .frame(height: scroller.bottomInset(viewportHeight: scrollGeometry?.containerSize.height ?? 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Layout.pageMargin)
            .padding(.top, Layout.Space.snug)
            .coordinateSpace(.named(Self.pageCoordinateSpace))
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, newValue in
            scrollGeometry = newValue
        }
        .background {
            // Grain is the page surface: fixed, covering the margins and the
            // empty space past the last block. Section 6 groups it with the
            // rules, but drawing it per text fragment would texture only where
            // there are words. Rules *are* per-fragment — PageTextLayoutFragment
            // puts them on real baselines, so they travel with the text.
            GrainOverlay(intensity: theme.grain)
        }
        .pageMeasure()
    }

    private var titleField: some View {
        TextField(
            "Title",
            text: $note.title,
            prompt: Text("Untitled").foregroundStyle(theme.inkTertiary)
        )
        .textFieldStyle(.plain)
        .versoText(.display)
        .foregroundStyle(theme.ink)
        .opacity(isFocusMode && session.isEditing ? Self.dimmedOpacity : 1)
        .padding(.bottom, Layout.Space.cosy)
        .onChange(of: note.title) { _, _ in note.touch() }
        .accessibilityLabel(Text("Note title"))
    }

    private static let dimmedOpacity: Double = 0.25

    /// Focus Mode dims other blocks; within the active block, the coordinator
    /// dims other paragraphs using rendering attributes.
    private func dimming(for block: Block) -> Double {
        guard isFocusMode, let active = session.activeBlockID, active != block.id else { return 1 }
        return Self.dimmedOpacity
    }

    // MARK: - Keyboard accessories

    @ViewBuilder
    private var keyboardAccessories: some View {
        VStack(spacing: Layout.Space.snug) {
            if let draft = session.linkDraft {
                WikiLinkSuggestions(
                    draft: draft,
                    session: session,
                    currentNoteID: note.id,
                    onCreateNote: createLinkedNote
                )
            }

            if session.isEditing {
                FormattingToolbar(session: session, linkedNote: linkedNote)
            }
        }
        .animation(motion.animation(.settle), value: session.isEditing)
        .animation(motion.animation(.settle), value: session.linkDraft)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(BlockRegistry.shared.implementedTypes, id: \.self) { type in
                    Button {
                        appendBlock(of: type)
                    } label: {
                        Label {
                            Text(type.displayName)
                        } icon: {
                            Image(systemName: type.systemImage)
                        }
                    }
                }
            } label: {
                Label("Add block", systemImage: "plus")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle(isOn: focusModeBinding) {
                    Label("Focus Mode", systemImage: "scope")
                }
                Button {
                    isReordering = true
                } label: {
                    Label("Reorder Blocks", systemImage: "arrow.up.arrow.down")
                }
            } label: {
                Label("Page options", systemImage: "ellipsis.circle")
            }
        }
    }

    private var focusModeBinding: Binding<Bool> {
        Binding(
            get: { isFocusMode },
            set: { newValue in
                motion.run(.settle) { isFocusMode = newValue }
            }
        )
    }

    // MARK: - Typewriter scroll

    /// Holds the caret on the anchor line. The caret is suppressed for the
    /// duration of the scroll so it does not sit blinking in one place while
    /// the page slides beneath it.
    private func followCaret(to caret: CGRect?) {
        guard let caret, let geometry = scrollGeometry else { return }

        guard let target = scroller.targetOffset(
            caretMidY: caret.midY,
            currentOffset: geometry.contentOffset.y,
            viewportHeight: geometry.containerSize.height,
            contentHeight: geometry.contentSize.height
        ) else { return }

        isCaretSuppressed = true
        withAnimation(motion.animation(.settle)) {
            scrollPosition.scrollTo(y: target)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(MotionToken.settle.duration * 1000)))
            isCaretSuppressed = false
        }
    }

    // MARK: - Mutation

    private func appendBlock(of type: BlockType) {
        guard let block = try? BlockRegistry.shared.makeBlock(of: type) else { return }
        context.insert(block)
        motion.run(.settle) {
            note.append(block)
            note.touch()
        }
    }

    /// Creating a note from an unresolved link. It starts from `blank` so the
    /// engine has no opinion about what a linked note should contain.
    private func createLinkedNote(_ title: String) -> Note? {
        guard let created = try? TemplateInstantiator.makeNote(
            from: TemplateCatalog.shared.blank,
            in: context
        ) else { return nil }
        created.title = title
        return created
    }

    /// The note a link under the caret points at, resolved so the formatting
    /// bar can offer a real `NavigationLink` rather than a button that has to
    /// reach for the navigation stack.
    private var linkedNote: Note? {
        guard let target = session.linkTarget else { return nil }
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == target })
        return try? context.fetch(descriptor).first
    }
}
