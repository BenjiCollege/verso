import PhotosUI
import SwiftUI

/// A picture, and what it is of.
struct ImageBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.motion) private var motion

    @State private var isPicking = false
    @State private var picked: PhotosPickerItem?
    @State private var failure: String?
    /// The page width, so an imported picture knows what height to reserve.
    @State private var pageWidth: CGFloat = 320

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<ImagePayload>) in
            VStack(alignment: .leading, spacing: Layout.Space.snug) {
                if let image = ImageStore.load(payload.wrappedValue.assetID) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: payload.wrappedValue.displayHeight)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: Layout.Radius.regular))
                        .accessibilityLabel(Text(describe(payload.wrappedValue)))
                        .contextMenu {
                            Button {
                                picked = nil
                                replace(payload)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }

                    TextField(
                        "Caption",
                        text: payload.caption,
                        prompt: Text("Caption").foregroundStyle(theme.inkTertiary)
                    )
                    .textFieldStyle(.plain)
                    .versoText(.footnote)
                    .foregroundStyle(theme.inkSecondary)
                } else {
                    placeholder
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
            .photosPicker(isPresented: $isPicking, selection: $picked, matching: .images)
            .onChange(of: picked) { _, item in
                guard let item else { return }
                load(item, into: payload)
            }
            .alert(
                "Couldn't add the image",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) { failure = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    private var placeholder: some View {
        Button {
            isPicking = true
        } label: {
            VStack(spacing: Layout.Space.snug) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: Layout.Space.loose, weight: .light))
                Text("Add a picture")
                    .versoText(.footnote)
            }
            .foregroundStyle(theme.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.Space.vast * 3)
            .background(theme.inset, in: .rect(cornerRadius: Layout.Radius.regular))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.Radius.regular)
                    .strokeBorder(theme.rule, style: StrokeStyle(lineWidth: Layout.hairline, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add a picture"))
    }

    private func describe(_ payload: ImagePayload) -> String {
        let described = payload.accessibilityDescription.isEmpty
            ? payload.caption
            : payload.accessibilityDescription
        return described.isEmpty ? String(localized: "Picture") : described
    }

    private func load(_ item: PhotosPickerItem, into payload: Binding<ImagePayload>) {
        Task { @MainActor in
            defer { picked = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failure = String(localized: "That image couldn't be read.")
                    return
                }
                // The old file goes with the old payload, or every replacement
                // leaves a picture on disk that nothing points at.
                ImageStore.delete(payload.wrappedValue.assetID)

                let imported = try ImageStore.importImage(data: data, atPageWidth: pageWidth)
                motion.run(.settle) {
                    payload.wrappedValue.assetID = imported.assetID
                    payload.wrappedValue.displayHeight = imported.displayHeight
                }
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func replace(_ payload: Binding<ImagePayload>) {
        ImageStore.delete(payload.wrappedValue.assetID)
        motion.run(.settle) { payload.wrappedValue.assetID = nil }
    }
}
