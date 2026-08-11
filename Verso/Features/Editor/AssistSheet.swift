import SwiftData
import SwiftUI

/// Summary, actions and tags for the note in front of you.
///
/// Everything here is *offered*. Section 7 says action extraction is offered,
/// not forced, and the same principle covers the rest: nothing on this sheet
/// changes the note until it is tapped.
struct AssistSheet: View {
    let note: Note

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(IntelligenceService.self) private var intelligence
    @Environment(HapticEngine.self) private var haptics

    @State private var summary: [String] = []
    @State private var actions: [String] = []
    @State private var tags: [String] = []
    @State private var accepted: Set<String> = []
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                if !summary.isEmpty {
                    Section("In three lines") {
                        ForEach(summary, id: \.self) { line in
                            Label(line, systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                                .versoText(.callout)
                                .foregroundStyle(theme.ink)
                        }
                    }
                }

                if !actions.isEmpty {
                    Section {
                        ForEach(actions, id: \.self) { action in
                            actionRow(action)
                        }
                    } header: {
                        Text("Things to do")
                    } footer: {
                        Text("Tap one to add it as a checklist item. Nothing is added unless you do.")
                    }
                }

                if !tags.isEmpty {
                    Section {
                        ForEach(tags, id: \.self) { tag in
                            tagRow(tag)
                        }
                    } header: {
                        Text("Tags that already exist")
                    } footer: {
                        Text("Verso only ever suggests tags you've used before.")
                    }
                }

                if hasLoaded && summary.isEmpty && actions.isEmpty && tags.isEmpty {
                    ContentUnavailableView(
                        "Nothing to suggest",
                        systemImage: "text.magnifyingglass",
                        description: Text("There isn't enough in this note yet.")
                    )
                }
            }
            .navigationTitle("Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if intelligence.isWorking && !hasLoaded {
                    ProgressView()
                }
            }
            .task {
                summary = await intelligence.summarise(note)
                actions = await intelligence.extractActions(from: note)
                tags = await intelligence.suggestTags(for: note, in: context)
                hasLoaded = true
            }
        }
    }

    private func actionRow(_ action: String) -> some View {
        let isAccepted = accepted.contains(action)

        return Button {
            addAction(action)
        } label: {
            HStack(spacing: Layout.Space.snug) {
                Image(systemName: isAccepted ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isAccepted ? theme.accent : theme.inkSecondary)
                Text(action)
                    .versoText(.callout)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isAccepted)
        .accessibilityHint(Text(isAccepted ? "Added" : "Adds this as a checklist item"))
    }

    private func tagRow(_ tag: String) -> some View {
        let isAccepted = (note.tags ?? []).contains { $0.name == tag }

        return Button {
            addTag(tag)
        } label: {
            HStack(spacing: Layout.Space.snug) {
                Image(systemName: isAccepted ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isAccepted ? theme.accent : theme.inkSecondary)
                Text(tag)
                    .versoText(.callout)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isAccepted)
    }

    /// Adds to the last checklist in the note, or makes one.
    private func addAction(_ action: String) {
        let target = note.orderedBlocks.last { $0.type == .checklist }

        if let target, var payload = try? target.decoded(as: ChecklistPayload.self) {
            payload.items.append(.init(label: action))
            try? target.store(payload)
        } else {
            var payload = ChecklistPayload(groupBy: .none, itemFields: [.note])
            payload.items = [.init(label: action)]
            guard let block = try? Block(payload) else { return }
            context.insert(block)
            note.append(block)
        }

        note.touch()
        accepted.insert(action)
        haptics.play(.checklistCheck)
    }

    private func addTag(_ name: String) {
        guard let tag = try? Tag.findOrCreate(named: name, in: context) else { return }
        var current = note.tags ?? []
        guard !current.contains(where: { $0.id == tag.id }) else { return }
        current.append(tag)
        note.tags = current
        note.touch()
    }
}

/// A bullet that is a bullet, rather than an SF Symbol pretending to be one.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.Space.snug) {
            Text(verbatim: "•")
            configuration.title
        }
    }
}
