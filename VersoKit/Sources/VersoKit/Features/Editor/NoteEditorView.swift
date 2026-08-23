import SwiftData
import SwiftUI
import UIKit

/// The page.
///
/// A `ScrollView` rather than a `List`, because typewriter scroll needs an
/// exact content offset and a `List` will not surrender one. Reordering moved
/// to `BlockReorderSheet` in exchange, which keeps drag-and-drop and VoiceOver
/// on a control built for it.
struct NoteEditorView: View {
    @Bindable var note: Note

    /// `nonisolated` because conforming to `View` infers `@MainActor` on the
    /// whole type, and `TextBlockView` reads this from inside the `@Sendable`
    /// transform of `onGeometryChange`. A name for a coordinate space is a
    /// constant string; it has no business being actor-isolated at all.
    nonisolated static let pageCoordinateSpace = "verso.page"

    @Environment(\.modelContext) private var context
    @Environment(\.themeCatalog) private var catalog
    @Environment(\.theme) private var appTheme
    @Environment(\.stock) private var appStock
    @Environment(\.motion) private var motion
    @Environment(AppearanceStore.self) private var appearance
    @Environment(LinkIndex.self) private var linkIndex
    @Environment(HapticEngine.self) private var haptics
    @Environment(VaultService.self) private var vault
    @Environment(IntelligenceService.self) private var intelligence
    @Environment(RecordingSession.self) private var recording

    /// Drives the measure, so the column widens with Dynamic Type rather than
    /// keeping 68 characters of ever-larger text on the same line length.
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = Typography.Role.body.pointSize

    @State private var session = TextEditingSession()
    @State private var blockActions = BlockActions()
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollGeometry: ScrollGeometry?
    @State private var isReordering = false
    @State private var isChangingLook = false
    @State private var isSavingTemplate = false
    @State private var isReading = false
    @State private var isExporting = false
    @State private var isShowingVaultGate = false
    @State private var isAssisting = false
    @State private var lockFailure: String?
    @State private var isFocusMode = false
    @State private var isCaretSuppressed = false
    /// Which version the fore-edge is previewing. `nil` is the present.
    @State private var scrubIndex: Int?
    @State private var scrubbedSnapshot: NoteSnapshot?

    private var versionStore: VersionStore { VersionStore(context: context) }

    /// Cached rather than computed.
    ///
    /// `body` reads this three times — the fore-edge, the page and the scrub
    /// bar — and computing it sorts the whole history, which the retention
    /// policy caps at 120. Sorting 120 objects three times per render, on
    /// every keystroke, to answer "how many are there" is work nobody asked
    /// for. History only changes when something records or restores, so it is
    /// refreshed there and when the relationship's count moves under us.
    @State private var versions: [Version] = []

    private func refreshVersions() {
        versions = versionStore.versions(of: note)
    }

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
        // A note carrying its own theme lights itself. One without inherits the
        // app's, which is already the theme's own appearance.
        .overlay(alignment: .bottom) {
            if blockActions.recovered != nil {
                BlockRecoveryBanner {
                    blockActions.undo(in: note, context: context)
                } onDismiss: {
                    blockActions.dismiss()
                }
                .padding(.bottom, Layout.Space.loose)
            }
        }
        .animation(motion.animation(.settle), value: blockActions.recovered)
        .versoTheme(theme, stock: stock)
        .environment(\.textEditingSession, session)
        .environment(\.editorFocusMode, isFocusMode)
        .environment(\.caretSuppressed, isCaretSuppressed)
        .navigationTitle(note.title.isEmpty ? String(localized: "Untitled") : note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isChromeHidden ? .hidden : .visible, for: .navigationBar)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) { keyboardAccessories }
        .sheet(isPresented: $isReordering) {
            BlockReorderSheet(note: note, actions: blockActions)
        }
        .sheet(isPresented: $isChangingLook) {
            NoteLookSheet(note: note)
        }
        // Focus Mode is a preference now, so a page opens the way the last one
        // did rather than resetting every time.
        .onAppear { isFocusMode = appearance.isFocusModeEnabled }
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
        .sheet(isPresented: $isAssisting) {
            AssistSheet(note: note)
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
        // Handoff and Spotlight both hang off this. `VersoActivity` decides
        // eligibility, so a locked note is advertised nowhere.
        .userActivity(VersoActivity.openNote) { activity in
            let built = VersoActivity.activity(for: note)
            activity.title = built.title
            activity.userInfo = built.userInfo
            activity.isEligibleForHandoff = built.isEligibleForHandoff
            activity.isEligibleForSearch = built.isEligibleForSearch
            activity.isEligibleForPrediction = built.isEligibleForPrediction
        }
        // Dropping text or a file into the page appends a block, so a snippet
        // from another app lands where it was aimed.
        .dropDestination(for: String.self) { items, _ in
            appendDroppedText(items.joined(separator: "\n\n"))
            return true
        }
        .onChange(of: note.versions?.count) { _, _ in
            refreshVersions()
        }
        .task {
            haptics.prepare()
            // The first version is the note as it was when opened, so there is
            // always something to scrub back to.
            versionStore.record(note)
            refreshVersions()
        }
        .onDisappear {
            versionStore.record(note)
            Task {
                // Section 7: auto-title on first save. Only ever fills an empty
                // title — overwriting one somebody chose would be the app
                // deciding it knows better.
                await intelligence.autoTitleIfNeeded(note)
                await linkIndex.noteDidChange(note.id)
            }
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
        // Restoring records the present first, so history grew — and pruning at
        // the retention limit can leave the count unchanged, which is why this
        // does not rely on `onChange` noticing.
        refreshVersions()
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
                            .blockActions(
                                canMoveUp: blockActions.canMove(block, in: note, by: -1),
                                canMoveDown: blockActions.canMove(block, in: note, by: 1),
                                moveUp: { move(block, by: -1) },
                                moveDown: { move(block, by: 1) },
                                duplicate: {
                                    blockActions.duplicate(block, in: note, context: context)
                                    haptics.play(.checklistCheck)
                                },
                                delete: {
                                    blockActions.delete(block, in: note, context: context)
                                    haptics.play(.noteDeleted)
                                }
                            )
                    }

                    BacklinksView(noteID: note.id)
                }

                Color.clear
                    .frame(height: scroller.bottomInset(viewportHeight: scrollGeometry?.containerSize.height ?? 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Layout.pageMargin)
            .padding(.top, Layout.Space.snug)
            // Turned sideways there is width to spare, and `pageMeasure` alone
            // spent all of it on margins — which is why rotating appeared to do
            // nothing. The column takes it as text up to the relaxed measure,
            // then stops and centres.
            .frame(maxWidth: Layout.measureWidth(
                atPointSize: bodySize,
                characters: Layout.relaxedMeasureCharacters
            ))
            .frame(maxWidth: .infinity)
            .coordinateSpace(.named(Self.pageCoordinateSpace))
        }
        // Dragging the page puts the keyboard away, which is the gesture people
        // already try first.
        .scrollDismissesKeyboard(.interactively)
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
                // And tapping bare paper puts it away too. This sits behind the
                // blocks, so a tap meant for a paragraph reaches the paragraph
                // and only the ones that miss — the margins, the space past the
                // last block — land here.
                .contentShape(.rect)
                .onTapGesture { dismissKeyboard() }
        }
    }

    /// Named rather than written inline: four trailing closures in the middle of
    /// a `LazyVStack` gave the type-checker more than it would take, and the
    /// error it produced named the `ScrollView` thirty lines above.
    private func move(_ block: Block, by offset: Int) {
        withAnimation(motion.animation(.settle)) {
            _ = blockActions.move(block, in: note, by: offset)
        }
    }

    /// Puts the keyboard away.
    ///
    /// There is no focus binding to clear: paragraphs are `UITextView`s behind a
    /// representable, so `@FocusState` never sees them. Asking the responder
    /// chain is the one thing that reaches all of them at once.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var titleField: some View {
        // `axis: .vertical` so the title wraps instead of truncating.
        //
        // A single-line field scrolls its text out of sight, and the title is
        // the largest thing on the page and the one a reader uses to know where
        // they are — "Meeting — Aug 22, 1…" is the worst possible thing to
        // shorten. Long titles were always reachable by typing one; the timed
        // templates just made it the default.
        TextField(
            "Title",
            text: $note.title,
            prompt: Text("Untitled").foregroundStyle(theme.inkTertiary),
            axis: .vertical
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

            if recording.isRecording(into: note) {
                recordingBar
            }

            if session.isEditing {
                FormattingToolbar(session: session, linkedNote: linkedNote)
            }
        }
        .animation(motion.animation(.settle), value: session.isEditing)
        .animation(motion.animation(.settle), value: session.linkDraft)
        .animation(motion.animation(.settle), value: scrubIndex)
    }

    /// Shown while recording, so it is never ambiguous whether the microphone
    /// is on.
    private var recordingBar: some View {
        HStack(spacing: Layout.Space.cosy) {
            Circle()
                .fill(theme.accent)
                .frame(width: Layout.Space.cosy, height: Layout.Space.cosy)

            Text("Recording · \(recording.elapsed.timerClockText)")
                .versoText(.metadata)
                .foregroundStyle(theme.ink)
                .monospacedDigit()

            Spacer(minLength: 0)

            Button("Cancel") { recording.cancel() }
                .versoText(.metadata)

            Button("Stop") {
                recording.stop(for: note, in: context, localOnly: appearance.keepAudioOnDevice)
                haptics.play(.checklistCheck)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, Layout.Space.regular)
        .padding(.vertical, Layout.Space.snug)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Recording in progress"))
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
                    isChangingLook = true
                } label: {
                    Label("Page Look", systemImage: "paintpalette")
                }
                // Always present, because it always works: with the on-device
                // model where there is one, and by ordinary text processing
                // everywhere else. Section 1 requires the fallback; hiding the
                // button on some devices would advertise its absence.
                if !note.isLocked {
                    Button {
                        isAssisting = true
                    } label: {
                        Label("Suggestions", systemImage: "sparkles")
                    }
                }

                if !recording.isRecording {
                    Button {
                        Task { await recording.start(for: note) }
                    } label: {
                        Label("Record", systemImage: "mic")
                    }
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

    /// Focus Mode, written through to the preference as well as to the page.
    ///
    /// The setter only moved the local `isFocusMode`, so the toggle worked for
    /// the life of the screen and reverted the next time a note was opened —
    /// under a comment at `onAppear` claiming a page opens the way the last one
    /// did. `AppearanceStore` is the thing that makes that comment true.
    private var focusModeBinding: Binding<Bool> {
        Binding(
            get: { isFocusMode },
            set: { newValue in
                appearance.isFocusModeEnabled = newValue
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

    /// Dropped text is structured the same way a paste is, so a list dropped in
    /// arrives as a list.
    private func appendDroppedText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Task { @MainActor in
            let captured = await intelligence.structure(text)
            guard let blocks = try? TemplateInstantiator.makeBlocks(from: captured.makeTemplate()) else { return }

            motion.run(.settle) {
                for block in blocks {
                    context.insert(block)
                    note.append(block)
                }
                note.touch()
            }
        }
    }

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
