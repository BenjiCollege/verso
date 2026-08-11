import SwiftData
import SwiftUI

/// Autocomplete for an open `[[`.
///
/// Offers existing notes first, then the option to create one. Creating from
/// here is what makes wiki links usable for thinking out loud — you name the
/// note you wish existed and it does.
struct WikiLinkSuggestions: View {
    let draft: WikiLink.Draft
    let session: TextEditingSession
    let currentNoteID: UUID
    let onCreateNote: (String) -> Note?

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    @Query(
        filter: #Predicate<Note> { !$0.isTrashed && !$0.isHidden },
        sort: [SortDescriptor(\Note.modifiedAt, order: .reverse)]
    )
    private var notes: [Note]

    private var query: String {
        draft.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prefix matches before contains-matches, most recently edited first
    /// within each. Capped so the list never eats the screen.
    private var suggestions: [Note] {
        let needle = query.lowercased()
        let candidates = notes.filter { $0.id != currentNoteID && !$0.title.isEmpty }
        guard !needle.isEmpty else { return Array(candidates.prefix(6)) }

        let prefixed = candidates.filter { $0.title.lowercased().hasPrefix(needle) }
        let contained = candidates.filter {
            let title = $0.title.lowercased()
            return !title.hasPrefix(needle) && title.contains(needle)
        }
        return Array((prefixed + contained).prefix(6))
    }

    private var canCreate: Bool {
        !query.isEmpty && !suggestions.contains { $0.title.lowercased() == query.lowercased() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { note in
                button(title: note.title, systemImage: "doc.text") {
                    session.completeLink(title: note.title, noteID: note.id)
                }
            }

            if canCreate {
                if !suggestions.isEmpty {
                    Divider().overlay(theme.rule)
                }
                button(title: String(localized: "Create “\(query)”"), systemImage: "plus.square") {
                    let created = onCreateNote(query)
                    session.completeLink(title: query, noteID: created?.id)
                }
            }

            if suggestions.isEmpty && !canCreate {
                Text("Keep typing to name a note")
                    .versoText(.chromeCaption)
                    .foregroundStyle(theme.inkSecondary)
                    .padding(Layout.Space.cosy)
            }
        }
        .background(.bar)
        .clipShape(.rect(cornerRadius: Layout.Radius.regular))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.Radius.regular)
                .strokeBorder(theme.rule, lineWidth: Layout.hairline)
        }
        .padding(.horizontal, Layout.Space.regular)
        .transition(motion.transition(.settle, motion: .move(edge: .bottom).combined(with: .opacity)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Note suggestions"))
    }

    private func button(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Layout.Space.snug) {
                Image(systemName: systemImage)
                    .foregroundStyle(theme.accent)
                Text(title)
                    .versoText(.chromeLabel)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.Space.cosy)
            .frame(minHeight: Layout.minimumHitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
