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
                    let doomed = offsets.map { note.orderedBlocks[$0] }
                    for block in doomed {
                        note.remove(block)
                        context.delete(block)
                    }
                    note.touch()
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
