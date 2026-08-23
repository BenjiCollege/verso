import SwiftUI

/// Reordering, moved out of the page.
///
/// Phase 1 reordered inside a `List`, which gave drag and VoiceOver for free.
/// The page is now a `ScrollView` — typewriter scroll needs an exact content
/// offset, which a `List` will not give up — so reordering became its own
/// screen. It reads better as one too: a compact index of the note, where the
/// blocks are short enough to compare.
struct BlockReorderSheet: View {
    @Bindable var note: Note

    /// The editor's own actions, passed in rather than made here.
    ///
    /// Deleting a block on the page records a snapshot and offers Undo for
    /// eight seconds; deleting the same block from this sheet used to be an
    /// outright `context.delete`. Same operation, same note, two different
    /// consequences depending on which screen you were looking at. Sharing the
    /// instance is what makes the banner appear when the sheet closes.
    let actions: BlockActions

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            List {
                ForEach(note.orderedBlocks) { block in
                    row(block)
                }
                .onMove { source, destination in
                    note.moveBlocks(fromOffsets: source, toOffset: destination)
                    note.touch()
                }
                .onDelete { offsets in
                    // Only the most recent deletion is recoverable, which is all
                    // a `List` row delete can produce — the minus and the swipe
                    // both act on one row at a time.
                    let doomed = offsets.map { note.orderedBlocks[$0] }
                    for block in doomed {
                        actions.delete(block, in: note, context: context)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Blocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ block: Block) -> some View {
        let summary = BlockRegistry.shared.plainText(for: block)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " · ")

        return HStack(spacing: Layout.Space.cosy) {
            Image(systemName: block.type?.systemImage ?? "questionmark.square.dashed")
                .foregroundStyle(theme.inkSecondary)
                .frame(width: Layout.Space.loose)

            VStack(alignment: .leading, spacing: Layout.Space.hair) {
                Text(block.type.map { String(localized: $0.displayName) } ?? block.typeRaw)
                    .versoText(.metadata)
                    .foregroundStyle(theme.inkSecondary)

                Text(summary.isEmpty ? String(localized: "Empty") : summary)
                    .versoText(.chromeLabel)
                    .foregroundStyle(summary.isEmpty ? theme.inkTertiary : theme.ink)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
