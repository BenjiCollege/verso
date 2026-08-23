import SwiftData
import SwiftUI

/// The filters, as a column.
///
/// The same `LibraryFilter` the phone shows as a horizontal chip bar. On a wide
/// screen a scrolling strip of chips is the wrong shape twice over: it hides
/// most of the folders behind a swipe on a display with room for all of them,
/// and it wastes the one thing an iPad has that a phone does not, which is a
/// place to put navigation that is always visible.
///
/// Deliberately *not* a shared component with `LibraryFilterBar`. They select
/// the same value and share nothing else — one is a scrolling row of capsules
/// sized for a thumb, the other a static list sized for a pointer, and folding
/// them together would mean a view that is good at neither.
struct LibrarySidebar: View {
    @Binding var filter: LibraryFilter
    let unfiledCount: Int

    /// Chrome the phone reaches through the toolbar's overflow menu. On iPad
    /// there is a column to put it in, and burying Settings behind a menu on a
    /// screen this size reads as a phone app that was stretched.
    let onSettings: () -> Void
    let onTrash: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    @Query(sort: [SortDescriptor(\Folder.position)]) private var folders: [Folder]
    @Query(sort: [SortDescriptor(\Tag.name)]) private var tags: [Tag]

    var body: some View {
        List {
            Section {
                row(title: String(localized: "All Notes"), icon: "square.stack", candidate: .all)
                if unfiledCount > 0 {
                    row(
                        title: String(localized: "Unfiled"),
                        icon: "tray",
                        candidate: .unfiled,
                        count: unfiledCount
                    )
                }
            }

            if !visibleFolders.isEmpty {
                Section {
                    ForEach(visibleFolders) { folder in
                        row(
                            title: folder.name,
                            icon: folder.icon,
                            candidate: .folder(folder.id),
                            count: folder.visibleNotes.count
                        )
                    }
                } header: {
                    SectionLabel(title: "Folders")
                }
            }

            if !tags.isEmpty {
                Section {
                    ForEach(tags) { tag in
                        row(title: tag.name, icon: "number", candidate: .tag(tag.id))
                    }
                } header: {
                    SectionLabel(title: "Tags")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.canvas.ignoresSafeArea())
        .navigationTitle("Verso")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Settings", systemImage: "gearshape", action: onSettings)
                    Button("Recently Deleted", systemImage: "trash", action: onTrash)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    /// Empty folders are hidden, matching the chip bar — a folder with nothing
    /// in it is a filter that leads to an empty screen.
    private var visibleFolders: [Folder] {
        folders.filter { !$0.visibleNotes.isEmpty }
    }

    private func row(
        title: String,
        icon: String,
        candidate: LibraryFilter,
        count: Int? = nil
    ) -> some View {
        let isSelected = filter == candidate

        return Button {
            // Unlike the chip bar, selecting the row you are on does *not*
            // clear the filter. A sidebar shows where you are; a persistent
            // selection that vanishes when you tap it would be a list that
            // argues with itself. "All Notes" is the way out, and it is always
            // on screen here — which is exactly what the chip bar lacked.
            motion.run(.snap) { filter = candidate }
        } label: {
            HStack(spacing: Layout.Space.cosy) {
                Image(systemName: icon)
                    .imageScale(.medium)
                    .foregroundStyle(isSelected ? theme.accent : theme.inkSecondary)
                    .frame(width: Layout.Space.loose)

                Text(title)
                    .versoText(.chromeBody)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)

                Spacer(minLength: Layout.Space.snug)

                if let count {
                    Text("\(count)")
                        .versoText(.metadata)
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .padding(.vertical, Layout.Space.hair)
            .frame(minHeight: Layout.minimumHitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected
                ? theme.accent.opacity(0.14)
                : Color.clear
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
