import SwiftData
import SwiftUI

/// The Phase 1 block editor.
///
/// Blocks are edited in a `List` so reordering and deletion come with the
/// system's drag, Edit-mode and VoiceOver affordances rather than a hand-rolled
/// approximation of them. Phase 2 replaces the text rows with a TextKit 2
/// `UITextView`; the surrounding structure stays.
struct NoteEditorView: View {
    @Bindable var note: Note

    @Environment(\.modelContext) private var context
    @Environment(\.themeCatalog) private var catalog
    @Environment(\.theme) private var appTheme
    @Environment(\.stock) private var appStock
    @Environment(\.motion) private var motion

    @State private var isEditing = false

    /// A note may pin its own theme; otherwise it inherits the app's.
    private var theme: Theme { catalog.theme(id: note.themeID) ?? appTheme }
    private var stock: Stock { catalog.stock(id: note.stockID) ?? appStock }

    var body: some View {
        ZStack {
            // Outside the measure, flat stock colour: the desk the page sits on.
            theme.stock.ignoresSafeArea()

            ZStack {
                // Rules are drawn behind the scroll rather than inside it, so
                // they do not travel with the text. Phase 2 moves them into
                // NSTextLayoutFragment rendering, which is where they belong.
                PageBackground()
                blockList
            }
            .pageMeasure()
        }
        .versoTheme(theme, stock: stock, pinnedColorScheme: note.themeID == nil ? nil : theme.colorScheme)
        .navigationTitle(note.title.isEmpty ? String(localized: "Untitled") : note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
    }

    // MARK: - List

    private var blockList: some View {
        List {
            Section {
                titleField
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets)
                    .moveDisabled(true)
                    .deleteDisabled(true)
            }

            Section {
                ForEach(note.orderedBlocks) { block in
                    BlockRenderer(block: block)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                }
                .onMove(perform: moveBlocks)
                .onDelete(perform: deleteBlocks)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, Layout.Space.airy)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: Layout.Space.tight,
            leading: Layout.pageMargin,
            bottom: Layout.Space.tight,
            trailing: Layout.pageMargin
        )
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
        .padding(.top, Layout.Space.snug)
        .padding(.bottom, Layout.Space.cosy)
        .onChange(of: note.title) { _, _ in note.touch() }
        .accessibilityLabel(Text("Note title"))
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
            Button {
                motion.run(.settle) { isEditing.toggle() }
            } label: {
                Label(isEditing ? "Done" : "Reorder", systemImage: isEditing ? "checkmark" : "arrow.up.arrow.down")
            }
            .accessibilityLabel(Text(isEditing ? "Finish reordering" : "Reorder blocks"))
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

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        note.moveBlocks(fromOffsets: source, toOffset: destination)
        note.touch()
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let doomed = offsets.map { note.orderedBlocks[$0] }
        motion.run(.settle) {
            for block in doomed {
                note.remove(block)
                context.delete(block)
            }
            note.touch()
        }
    }
}
