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
    @Environment(HapticEngine.self) private var haptics
    @Environment(VaultService.self) private var vault

    @State private var session = TextEditingSession()
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollGeometry: ScrollGeometry?
    @State private var isReordering = false
    @State private var isSavingTemplate = false
    @State private var isReading = false
    @State private var isExporting = false
    @State private var isShowingVaultGate = false
    @State private var lockFailure: String?
    @State private var isFocusMode = false
    @State private var isCaretSuppressed = false
    /// Which version the fore-edge is previewing. `nil` is the present.
    @State private var scrubIndex: Int?
    @State private var scrubbedSnapshot: NoteSnapshot?

    private var versionStore: VersionStore { VersionStore(context: context) }
    private var versions: [Version] { versionStore.versions(of: note) }

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

            // A locked note shows nothing until the vault is open. Its bytes
            // are ciphertext, so there is genuinely nothing to show.
            if note.isLocked && vault.state != .unlocked {
                LockedNoteView(note: note)
            } else {
                HStack(spacing: 0) {
                    foreEdge
                    page
                }
            }
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
        .sheet(isPresented: $isSavingTemplate) {
            SaveAsTemplateSheet(note: note)
        }
        .sheet(isPresented: $isExporting) {
            ExportSheet(note: note)
        }
        .fullScreenCover(isPresented: $isReading) {
            ReadModeView(note: note)
        }
        .sheet(isPresented: $isShowingVaultGate) {
            VaultGateView()
        }
        .alert(
            "Couldn't change the lock",
            isPresented: Binding(get: { lockFailure != nil }, set: { if !$0 { lockFailure = nil } }),
            presenting: lockFailure
        ) { _ in
            Button("OK", role: .cancel) { lockFailure = nil }
        } message: { message in
            Text(message)
        }
        .onChange(of: note.isLocked) { _, isLocked in
            vault.isViewingLockedNote = isLocked
        }
        .onChange(of: session.caretRectInPage) { _, caret in
            followCaret(to: caret)
        }
        .onChange(of: scrubIndex) { _, index in
            scrubbedSnapshot = index.flatMap { versionStore.snapshot(at: $0, of: note) }
        }
        .task {
            haptics.prepare()
            // The first version is the note as it was when opened, so there is
            // always something to scrub back to.
            versionStore.record(note)
        }
        .onDisappear {
            versionStore.record(note)
            Task { await linkIndex.noteDidChange(note.id) }
        }
    }

    // MARK: - Fore-edge

    private var foreEdge: some View {
        ForeEdgeView(
            model: ForeEdgeModel.make(
                readableLength: NoteSnapshot(note).readableLength,
                themeID: theme.id,
                isLocked: note.isLocked
            ),
            versionCount: versions.count,
            scrubIndex: $scrubIndex
        )
        .padding(.leading, Layout.Space.tight)
        .opacity(isChromeHidden ? 0 : 1)
        .animation(motion.animation(.settle), value: isChromeHidden)
    }

    /// Locking needs the vault open, because encrypting requires the key just
    /// as much as decrypting does. If it is closed, the gate is shown instead
    /// of a failure.
    private func toggleLock() {
        guard vault.state == .unlocked else {
            isShowingVaultGate = true
            return
        }

        do {
            if note.isLocked {
                try vault.unlockNote(note)
            } else {
                try vault.lockNote(note)
            }
            haptics.play(.vaultClasp)
        } catch {
            lockFailure = error.localizedDescription
        }
    }

    private func restoreScrubbedVersion() {
        guard let snapshot = scrubbedSnapshot else { return }
        motion.run(.pageTurn) {
            versionStore.restore(snapshot, to: note)
            scrubIndex = nil
            scrubbedSnapshot = nil
        }
        haptics.play(.vaultClasp)
    }

    // MARK: - Page

    private var page: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Layout.Space.snug) {
                if let scrubbedSnapshot, let index = scrubIndex, versions.indices.contains(index) {
                    // Content morphs backward in time as the thumb travels. The
                    // transition is a cross-fade under Reduce Motion.
                    VersionPreview(snapshot: scrubbedSnapshot, recordedAt: versions[index].createdAt)
                        .transition(motion.transition(.pageTurn, motion: .opacity))
                        .id(index)
                } else {
                    titleField

                    ForEach(note.orderedBlocks) { block in
                        BlockRenderer(block: block)
                            .opacity(dimming(for: block))
                            .animation(motion.animation(.settle), value: isChromeHidden)
                            .animation(motion.animation(.settle), value: session.activeBlockID)
                    }

                    BacklinksView(noteID: note.id)
                }

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
            if let index = scrubIndex, versions.indices.contains(index) {
                VersionScrubBar(
                    recordedAt: versions[index].createdAt,
                    onRestore: restoreScrubbedVersion,
                    onDismiss: {
                        motion.run(.pageTurn) {
                            scrubIndex = nil
                            scrubbedSnapshot = nil
                        }
                    }
                )
                .transition(motion.transition(.settle, motion: .move(edge: .bottom).combined(with: .opacity)))
            }

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
        .animation(motion.animation(.settle), value: scrubIndex)
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
                Button {
                    isReading = true
                } label: {
                    Label("Read Mode", systemImage: "book.pages")
                }
                // A locked note cannot be shared even while the vault is open.
                // The point of locking it was to keep it in.
                if VaultPolicy.isEligibleForSharing(note) {
                    Button {
                        isExporting = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    toggleLock()
                } label: {
                    Label(
                        note.isLocked ? "Remove Lock" : "Lock Note",
                        systemImage: note.isLocked ? "lock.open" : "lock"
                    )
                }

                Divider()

                Picker("Reveal", selection: revealStyleBinding) {
                    ForEach(RevealStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                Button {
                    isSavingTemplate = true
                } label: {
                    Label("Save as Template", systemImage: "square.on.square")
                }
            } label: {
                Label("Page options", systemImage: "ellipsis.circle")
            }
        }
    }

    /// The reveal is a property of the note, so a journal can unfurl and a
    /// shopping list can stay still.
    private var revealStyleBinding: Binding<RevealStyle> {
        Binding(
            get: { RevealStyle(rawValue: note.revealStyleID ?? "") ?? .fadeUp },
            set: { newValue in
                note.revealStyleID = newValue.rawValue
                note.touch()
            }
        )
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
