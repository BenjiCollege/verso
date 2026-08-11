import SwiftUI

struct NoteRowView: View {
    let note: Note

    @Environment(\.theme) private var theme

    /// The first line of readable content, whatever block it came from. Uses
    /// the registry rather than looking for a text block, so a note that opens
    /// with a checklist still previews.
    private var preview: String {
        for block in note.orderedBlocks {
            let text = BlockRegistry.shared.plainText(for: block)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text.replacingOccurrences(of: "\n", with: " · ")
            }
        }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.tight) {
            HStack(spacing: Layout.Space.snug) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                }

                Text(note.title.isEmpty ? String(localized: "Untitled") : note.title)
                    .versoText(.chromeBody)
                    .foregroundStyle(note.title.isEmpty ? theme.inkSecondary : theme.ink)
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
        .accessibilityLabel(Text(note.title.isEmpty ? String(localized: "Untitled note") : note.title))
        .accessibilityValue(Text(preview))
        .accessibilityAddTraits(note.isPinned ? [.isSelected] : [])
    }
}
