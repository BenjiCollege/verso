import SwiftData
import SwiftUI

/// The scope strip above the library.
///
/// Horizontal and scrolling, unlike the tag editor, because this one is a
/// control rather than a list: only the selected chip has to be visible, and a
/// strip that wraps to three lines pushes the notes off the screen they are
/// the point of.
struct LibraryFilterBar: View {
    @Binding var filter: LibraryFilter
    let unfiledCount: Int

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    @Query(sort: [SortDescriptor(\Folder.position)]) private var folders: [Folder]
    @Query(sort: [SortDescriptor(\Tag.name)]) private var tags: [Tag]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Layout.Space.snug) {
                chip(title: String(localized: "All"), icon: "square.stack", filter: .all)

                ForEach(folders) { folder in
                    let count = folder.visibleNotes.count
                    if count > 0 {
                        chip(title: folder.name, icon: folder.icon, filter: .folder(folder.id), count: count)
                    }
                }

                ForEach(tags) { tag in
                    let count = (tag.notes ?? []).count(where: { !$0.isTrashed && !$0.isHidden })
                    if count > 0 {
                        chip(title: tag.name, icon: "number", filter: .tag(tag.id), count: count)
                    }
                }

                // Last, because it is the pile you deal with rather than the
                // one you browse — and it disappears once it is empty, which is
                // the only reward filing offers.
                if unfiledCount > 0 {
                    chip(title: String(localized: "Unfiled"), icon: "tray", filter: .unfiled, count: unfiledCount)
                }
            }
            .padding(.horizontal, Layout.Space.regular)
            .padding(.vertical, Layout.Space.snug)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(
        title: String,
        icon: String,
        filter candidate: LibraryFilter,
        count: Int? = nil
    ) -> some View {
        let isSelected = filter == candidate

        return Button {
            motion.run(.snap) {
                // Tapping the chip you are on goes back to everything, so the
                // way out is the way in.
                filter = isSelected ? .all : candidate
            }
        } label: {
            HStack(spacing: Layout.Space.tight) {
                Image(systemName: icon)
                    .imageScale(.small)
                Text(title)
                if let count {
                    Text("\(count)")
                        .foregroundStyle(isSelected ? theme.stock.opacity(0.7) : theme.inkTertiary)
                }
            }
            .versoText(.chromeCaption)
            .foregroundStyle(isSelected ? theme.stock : theme.inkSecondary)
            .padding(.horizontal, Layout.Space.cosy)
            .padding(.vertical, Layout.Space.snug)
            .background(
                isSelected ? theme.accent : theme.card,
                in: .rect(cornerRadius: Layout.Radius.capsule)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.Radius.capsule)
                    .strokeBorder(isSelected ? .clear : theme.cardBorder, lineWidth: Layout.hairline)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
