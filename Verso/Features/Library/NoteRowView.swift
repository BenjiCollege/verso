import SwiftUI

struct NoteRowView: View {
    let note: Note

    @Environment(\.theme) private var theme

    /// The first line of readable content, whatever block it came from.
    ///
    /// Routed through `VaultPolicy`, so a locked note shows nothing here
    /// whether or not the vault happens to be open — a list is a place someone
    /// else can read over your shoulder.
    private var preview: String {
        VaultPolicy.listPreview(for: note)
    }

    private var title: String {
        let resolved = VaultPolicy.listTitle(for: note)
        return resolved.isEmpty ? String(localized: "Untitled") : resolved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.tight) {
            HStack(spacing: Layout.Space.snug) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                }

                if note.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(theme.gilt)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .versoText(.chromeBody)
                    .foregroundStyle(note.title.isEmpty || note.isLocked ? theme.inkSecondary : theme.ink)
                    .lineLimit(1)
            }

            if !preview.isEmpty {
                Text(preview)
                    .versoText(.chromeLabel)
                    .foregroundStyle(theme.inkSecondary)
                    .lineLimit(2)
            }

            Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                .versoText(.metadata)
                .foregroundStyle(theme.inkTertiary)
        }
        .padding(.vertical, Layout.Space.tight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(preview))
        .accessibilityHint(note.isLocked ? Text("Locked. Opening it needs the vault.") : Text(""))
        .accessibilityAddTraits(note.isPinned ? [.isSelected] : [])
    }
}
