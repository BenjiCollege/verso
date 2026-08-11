import SwiftUI
import UniformTypeIdentifiers

struct AttachmentBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme

    @State private var isImporting = false
    @State private var isViewing = false
    @State private var failure: String?

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<AttachmentPayload>) in
            Group {
                if payload.wrappedValue.isEmpty {
                    importButton
                } else {
                    card(payload)
                }
            }
            .padding(.vertical, Layout.Space.tight)
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: DocumentStore.acceptedTypes
            ) { result in
                guard case .success(let url) = result else { return }
                do {
                    payload.wrappedValue = try DocumentStore.importDocument(from: url)
                } catch {
                    failure = error.localizedDescription
                }
            }
            .sheet(isPresented: $isViewing) {
                DocumentViewer(payload: payload)
            }
            .alert(
                "Couldn't open that",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) { failure = nil }
            } message: { Text($0) }
        }
    }

    private var importButton: some View {
        Button {
            isImporting = true
        } label: {
            Label("Add a PDF", systemImage: "doc.badge.plus")
                .versoText(.callout)
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity, minHeight: Layout.minimumHitTarget * 1.5)
                .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.tight))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.Radius.tight)
                        .strokeBorder(theme.rule, style: StrokeStyle(lineWidth: Layout.hairline, dash: [4, 3]))
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func card(_ payload: Binding<AttachmentPayload>) -> some View {
        let value = payload.wrappedValue
        let isPresent = DocumentStore.exists(value.assetID)

        return Button {
            isViewing = true
        } label: {
            HStack(spacing: Layout.Space.cosy) {
                thumbnail(value)

                VStack(alignment: .leading, spacing: Layout.Space.hair) {
                    Text(value.displayName)
                        .versoText(.callout)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)

                    Text("\(value.pageCount) \(value.pageCount == 1 ? "page" : "pages") · \(value.sizeDescription)")
                        .versoText(.metadata)
                        .foregroundStyle(theme.inkSecondary)

                    if !isPresent {
                        // Section 5 describes an attachment as a file ref, so a
                        // document stays on the device it was imported to.
                        // Saying so beats a viewer that opens onto nothing.
                        Text("Not on this device")
                            .versoText(.metadata)
                            .foregroundStyle(theme.inkTertiary)
                    } else if !value.annotations.isEmpty {
                        Text("\(value.annotations.highlights.count) highlights · \(value.annotations.annotatedPages.count) marked pages")
                            .versoText(.metadata)
                            .foregroundStyle(theme.inkTertiary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(Layout.Space.snug)
            .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.tight))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(value.displayName))
        .accessibilityHint(Text(isPresent ? "Double tap to read and mark up" : "Not on this device"))
    }

    @ViewBuilder
    private func thumbnail(_ payload: AttachmentPayload) -> some View {
        if let image = UIImage(data: payload.thumbnail) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Layout.Space.airy, height: Layout.Space.vast)
                .clipShape(.rect(cornerRadius: Layout.Radius.tight / 2))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.Radius.tight / 2)
                        .strokeBorder(theme.rule, lineWidth: Layout.hairline)
                }
        } else {
            Image(systemName: "doc.richtext")
                .font(.system(size: Layout.Space.loose))
                .foregroundStyle(theme.inkSecondary)
                .frame(width: Layout.Space.airy, height: Layout.Space.vast)
        }
    }
}
