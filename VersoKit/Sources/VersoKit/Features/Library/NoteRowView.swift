import SwiftUI

/// One note, as a card.
///
/// Ordered the way a note is recognised: what it is, what's in it, then what
/// it's filed under and when you last touched it. Everything after the title is
/// optional — a note with no preview and no tags collapses to a single line
/// rather than reserving space for absences.
struct NoteRowView: View {
    let note: Note
    /// Why this note matched a search, when it came from one.
    var excerpt: String = ""

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

    /// Tags are the note's own, and a locked note's are as private as its text.
    private var tags: [Tag] {
        guard VaultPolicy.isEligibleForIndexing(note) else { return [] }
        return (note.tags ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Space.snug) {
            HStack(spacing: Layout.Space.snug) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .imageScale(.small)
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                }

                if note.isLocked {
                    Image(systemName: "lock.fill")
                        .imageScale(.small)
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
                    .multilineTextAlignment(.leading)
            }

            if !excerpt.isEmpty {
                Text(excerpt)
                    .versoText(.chromeCaption)
                    .foregroundStyle(theme.inkSecondary)
                    .lineLimit(2)
                    .padding(.leading, Layout.Space.snug)
                    .overlay(alignment: .leading) {
                        // A quoted line, marked as one.
                        Rectangle()
                            .fill(theme.accent)
                            .frame(width: Layout.hairline * 4)
                    }
            }

            HStack(spacing: Layout.Space.snug) {
                // Two, then a count. A note with nine tags would otherwise wrap
                // the row to three lines and bury the note it belongs to.
                ForEach(tags.prefix(2)) { tag in
                    VersoPill(title: tag.name)
                }
                if tags.count > 2 {
                    VersoPill(title: "+\(tags.count - 2)")
                }

                Spacer(minLength: 0)

                Text(note.modifiedAt.relativeDescription)
                    .versoText(.metadata)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .versoCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(preview))
        .accessibilityHint(note.isLocked ? Text("Locked. Opening it needs the vault.") : Text(""))
        .accessibilityAddTraits(note.isPinned ? [.isSelected] : [])
    }
}
