import SwiftUI

/// Flattened or layered, then out through `ShareLink` as a file.
struct DocumentExportSheet: View {
    let payload: AttachmentPayload

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var mode: DocumentExporter.Mode = .flattened
    @State private var exported: URL?
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(DocumentExporter.Mode.allCases) { candidate in
                        row(candidate)
                    }
                } footer: {
                    Text("Either way it's a file that leaves your device only when you send it.")
                }

                Section {
                    if let exported {
                        ShareLink(item: exported) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            prepare()
                        } label: {
                            HStack {
                                Label("Prepare", systemImage: "doc.badge.arrow.up")
                                if isWorking {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isWorking)
                    }
                }

                if let failure {
                    Section { Text(failure).foregroundStyle(theme.accent) }
                }
            }
            .navigationTitle("Export Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: mode) { _, _ in
                exported = nil
                failure = nil
            }
        }
    }

    private func row(_ candidate: DocumentExporter.Mode) -> some View {
        Button {
            mode = candidate
        } label: {
            HStack(spacing: Layout.Space.cosy) {
                VStack(alignment: .leading, spacing: Layout.Space.hair) {
                    Text(candidate.displayName)
                        .versoText(.chromeBody)
                        .foregroundStyle(theme.ink)
                    Text(candidate.summary)
                        .versoText(.chromeCaption)
                        .foregroundStyle(theme.inkSecondary)
                }
                Spacer(minLength: 0)
                if mode == candidate {
                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(mode == candidate ? [.isSelected] : [])
    }

    private func prepare() {
        isWorking = true
        failure = nil

        Task { @MainActor in
            defer { isWorking = false }
            do {
                let data = try DocumentExporter.export(payload, mode: mode, theme: theme)
                let url = URL.temporaryDirectory
                    .appending(path: DocumentExporter.fileName(for: payload, mode: mode))
                try data.write(to: url, options: .atomic)
                exported = url
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
