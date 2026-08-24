import SwiftUI
import UniformTypeIdentifiers

struct AttachmentBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme

    @State private var isImporting = false
    @State private var isScanning = false
    @State private var isViewing = false
    @State private var failure: String?

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<AttachmentPayload>) in
            Group {
                if payload.wrappedValue.isEmpty {
                    addAffordance
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
            // Not a sheet: the document camera is a full-screen viewfinder with
            // its own Cancel, and a card that can be swiped half away mid-shot
            // is not what it was drawn for.
            .fullScreenCover(isPresented: $isScanning) {
                DocumentScannerView { outcome in
                    isScanning = false
                    handle(outcome, into: payload)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isViewing) {
                DocumentViewer(payload: payload)
            }
            .alert(
                "Couldn't add that",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) { failure = nil }
            } message: { Text($0) }
        }
    }

    private func handle(_ outcome: DocumentScannerView.Outcome, into payload: Binding<AttachmentPayload>) {
        switch outcome {
        case .scanned(let pages):
            do {
                payload.wrappedValue = try DocumentStore.importScan(pages: pages)
            } catch {
                failure = error.localizedDescription
            }
        case .cancelled:
            // Backing out of the camera is not a failure and gets no alert.
            break
        case .failed(let error):
            failure = error.localizedDescription
        }
    }

    @ViewBuilder
    private var addAffordance: some View {
        if DocumentScannerView.isSupported {
            Menu {
                Button {
                    isImporting = true
                } label: {
                    Label("Choose File", systemImage: "folder")
                }

                Button {
                    isScanning = true
                } label: {
                    Label("Scan Document", systemImage: "doc.viewfinder")
                }
            } label: {
                addLabel
            }
            .accessibilityLabel(Text("Add a PDF"))
            .accessibilityHint(Text("Choose a file, or photograph one with the camera"))
        } else {
            // No camera — the simulator, and any device whose one is
            // unavailable. A menu with a single item is a worse button than a
            // button, so the affordance goes back to what it was.
            Button {
                isImporting = true
            } label: {
                addLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var addLabel: some View {
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
