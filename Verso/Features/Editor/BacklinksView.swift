import SwiftData
import SwiftUI

/// Notes that link here.
///
/// Sits at the foot of the page rather than behind a button: a backlink you
/// have to go looking for is a backlink you forget exists.
struct BacklinksView: View {
    let noteID: UUID

    @Environment(LinkIndex.self) private var index
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context

    @State private var sources: [Note] = []

    var body: some View {
        Group {
            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: Layout.Space.snug) {
                    Text("Linked from")
                        .versoText(.metadata)
                        .foregroundStyle(theme.inkSecondary)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(sources) { note in
                        NavigationLink(value: note) {
                            HStack(spacing: Layout.Space.snug) {
                                Image(systemName: "arrow.turn.up.left")
                                    .foregroundStyle(theme.accent)
                                Text(note.title.isEmpty ? String(localized: "Untitled") : note.title)
                                    .versoText(.callout)
                                    .foregroundStyle(theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: Layout.minimumHitTarget)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Layout.Space.loose)
            }
        }
        .task(id: noteID) {
            await index.buildIfNeeded()
            reload()
        }
        .onChange(of: index.graph) { _, _ in reload() }
    }

    private func reload() {
        let ids = index.backlinks(to: noteID)
        guard !ids.isEmpty else {
            sources = []
            return
        }
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { !$0.isTrashed && !$0.isHidden },
            sortBy: [SortDescriptor(\Note.modifiedAt, order: .reverse)]
        )
        sources = ((try? context.fetch(descriptor)) ?? []).filter { ids.contains($0.id) }
    }
}
