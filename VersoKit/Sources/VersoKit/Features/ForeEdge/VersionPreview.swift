import SwiftUI

/// The note as it was, rendered read-only.
///
/// Detached `Block` objects are built from the snapshot and handed to the same
/// `BlockRenderer` the live page uses — so a past version looks exactly like a
/// present one, and a block type added later renders in history for free. They
/// belong to no `ModelContext`, so nothing here can write to the store even if
/// a view tried.
struct VersionPreview: View {
    let snapshot: NoteSnapshot
    let recordedAt: Date

    @Environment(\.theme) private var theme

    private var blocks: [Block] {
        snapshot.blocks
            .sorted { $0.position < $1.position }
            .map { Block(id: $0.id, position: $0.position, typeRaw: $0.type, payload: $0.payload) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.snug) {
            Text(snapshot.title.isEmpty ? String(localized: "Untitled") : snapshot.title)
                .versoText(.display)
                .foregroundStyle(theme.ink)
                .padding(.bottom, Layout.Space.cosy)

            ForEach(blocks) { block in
                BlockRenderer(block: block)
            }
        }
        // Read-only twice over: nothing can be typed into it, and nothing can
        // be tapped in it.
        .disabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Version from \(recordedAt.formatted(date: .abbreviated, time: .shortened))"))
    }
}

/// The bar that appears when the thumb lets go on a past version.
///
/// Dragging previews; it never silently overwrites. Restoring is a decision,
/// and it is reversible — `VersionStore.restore` records the present first.
struct VersionScrubBar: View {
    let recordedAt: Date
    let onRestore: () -> Void
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Layout.Space.cosy) {
            VStack(alignment: .leading, spacing: Layout.Space.hair) {
                Text("Viewing an earlier version")
                    .versoText(.chromeLabel)
                    .foregroundStyle(theme.ink)
                Text(recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .versoText(.metadata)
                    .foregroundStyle(theme.inkSecondary)
            }

            Spacer(minLength: 0)

            Button("Back to Now", action: onDismiss)
                .buttonStyle(.bordered)

            Button("Restore", action: onRestore)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, Layout.Space.regular)
        .padding(.vertical, Layout.Space.snug)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }
}
