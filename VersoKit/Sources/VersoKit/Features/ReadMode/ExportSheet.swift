import SwiftUI

/// Choosing what to share.
///
/// Everything leaves as a file through `ShareLink`. Nothing is uploaded, there
/// is no link to expire, and no copy of the note exists anywhere but on the
/// device it was made on and in the user's own iCloud.
struct ExportSheet: View {
    let note: Note

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.stock) private var stock
    @Environment(\.themeCatalog) private var catalog
    @Environment(\.motion) private var motion

    @State private var format: NoteExporter.Format = .markdown
    @State private var exported: URL?
    @State private var isWorking = false
    @State private var failure: String?

    private var noteTheme: Theme { catalog.theme(id: note.themeID) ?? theme }
    private var noteStock: Stock { catalog.stock(id: note.stockID) ?? stock }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(NoteExporter.Format.allCases) { candidate in
                        row(candidate)
                    }
                } footer: {
                    Text("No server. A share is a file, and it leaves only when you send it.")
                }

                if format == .markdown {
                    Section("Preview") {
                        Text(NoteExporter.markdown(for: note))
                            .versoText(.metadata)
                            .foregroundStyle(theme.inkSecondary)
                            .lineLimit(12)
                            .textSelection(.enabled)
                    }
                }

                if let failure {
                    Section {
                        Text(failure).foregroundStyle(theme.accent)
                    }
                }

                Section {
                    if let exported {
                        ShareLink(item: exported) {
                            Label("Share \(String(localized: format.displayName))", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            prepare()
                        } label: {
                            HStack {
                                Label("Prepare", systemImage: format.systemImage)
                                if isWorking {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isWorking)
                    }
                }
            }
            .listRowBackground(theme.card)
            .scrollContentBackground(.hidden)
            .background(theme.canvas.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: format) { _, _ in
                exported = nil
                failure = nil
            }
        }
    }

    private func row(_ candidate: NoteExporter.Format) -> some View {
        Button {
            motion.run(.snap) { format = candidate }
        } label: {
            HStack(spacing: Layout.Space.cosy) {
                // The same tinted tile the gallery uses, so a chooser is a
                // chooser wherever you meet one.
                Image(systemName: candidate.systemImage)
                    .font(.system(size: Layout.Space.regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: Layout.Space.airy, height: Layout.Space.airy)
                    .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.tight))

                VStack(alignment: .leading, spacing: Layout.Space.tight) {
                    Text(candidate.displayName)
                        .versoText(.chromeBody)
                        .foregroundStyle(theme.ink)
                    Text(candidate.summary)
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)
                }

                Spacer(minLength: 0)

                if format == candidate {
                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(format == candidate ? [.isSelected] : [])
    }

    /// Rendering a PDF or a card is slow enough to be worth a spinner, and it
    /// happens on demand rather than on every appearance of this sheet.
    private func prepare() {
        isWorking = true
        failure = nil

        Task { @MainActor in
            defer { isWorking = false }
            do {
                let data: Data?
                switch format {
                case .markdown:
                    data = Data(NoteExporter.markdown(for: note).utf8)
                case .pdf:
                    data = NoteExporter.pdf(for: note, theme: noteTheme, stock: noteStock)
                case .image:
                    data = NoteExporter.image(for: note, theme: noteTheme, stock: noteStock)
                case .shareCard:
                    data = NoteExporter.shareCard(
                        for: note,
                        theme: noteTheme,
                        stock: noteStock,
                        style: motion.revealStyle(
                            RevealStyle(rawValue: note.revealStyleID ?? "") ?? .fadeUp
                        )
                    )
                }

                guard let data else {
                    failure = String(localized: "That couldn't be prepared. Try another format.")
                    return
                }
                exported = try NoteExporter.write(data, for: note, format: format)
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
