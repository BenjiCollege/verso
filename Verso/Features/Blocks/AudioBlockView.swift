import SwiftData
import SwiftUI

struct AudioBlockView: View {
    let block: Block

    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(ReplaySession.self) private var replay

    @State private var failure: String?

    var body: some View {
        BlockPayloadEditor(block: block) { (payload: Binding<AudioPayload>) in
            let asset = self.asset(for: payload.wrappedValue)

            HStack(spacing: Layout.Space.cosy) {
                transport(asset)

                VStack(alignment: .leading, spacing: Layout.Space.hair) {
                    TextField(
                        "Label",
                        text: payload.label,
                        prompt: Text("Recording").foregroundStyle(theme.inkTertiary)
                    )
                    .textFieldStyle(.plain)
                    .versoText(.callout)
                    .foregroundStyle(theme.ink)

                    if let asset {
                        Text(caption(for: asset))
                            .versoText(.metadata)
                            .foregroundStyle(theme.inkSecondary)
                    } else {
                        Text("This recording isn't on this device")
                            .versoText(.metadata)
                            .foregroundStyle(theme.inkTertiary)
                    }
                }

                Spacer(minLength: 0)

                if let asset {
                    menu(for: asset)
                }
            }
            .padding(.vertical, Layout.Space.tight)
            .overlay(alignment: .bottom) {
                if let asset, replay.isPlaying(asset) {
                    progressBar
                }
            }
            .alert(
                "Couldn't change that",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
                presenting: failure
            ) { _ in
                Button("OK", role: .cancel) { failure = nil }
            } message: { Text($0) }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func transport(_ asset: AudioAsset?) -> some View {
        Button {
            guard let asset else { return }
            if replay.isPlaying(asset) {
                replay.pause()
            } else if replay.assetID == asset.id {
                replay.resume()
            } else {
                replay.start(asset)
            }
        } label: {
            Image(systemName: asset.map { replay.isPlaying($0) } == true ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: Layout.Space.airy))
                .foregroundStyle(asset == nil ? theme.inkTertiary : theme.accent)
                .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(asset == nil)
        .accessibilityLabel(Text(asset.map { replay.isPlaying($0) } == true ? "Pause" : "Play"))
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.inset)
                Capsule()
                    .fill(theme.accent)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: Layout.hairline * 4)
        .accessibilityHidden(true)
    }

    private var fraction: Double {
        guard replay.duration > 0 else { return 0 }
        return min(max(replay.time / replay.duration, 0), 1)
    }

    private func menu(for asset: AudioAsset) -> some View {
        Menu {
            // Section 7's per-note toggle. Turning it on takes the bytes out of
            // the store, so the recording stops leaving this device at all.
            Toggle(isOn: Binding(
                get: { asset.localOnly },
                set: { newValue in
                    do {
                        try AudioStore.setLocalOnly(newValue, for: asset)
                    } catch {
                        failure = error.localizedDescription
                    }
                }
            )) {
                Label("Keep on this device only", systemImage: "iphone")
            }

            Button(role: .destructive) {
                AudioStore.delete(asset)
                context.delete(asset)
            } label: {
                Label("Delete Recording", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(theme.inkSecondary)
                .frame(minWidth: Layout.minimumHitTarget, minHeight: Layout.minimumHitTarget)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text("Recording options"))
    }

    // MARK: - Data

    private func asset(for payload: AudioPayload) -> AudioAsset? {
        guard let assetID = payload.assetID else { return nil }
        let descriptor = FetchDescriptor<AudioAsset>(predicate: #Predicate { $0.id == assetID })
        return try? context.fetch(descriptor).first
    }

    private func caption(for asset: AudioAsset) -> String {
        var parts = [asset.duration.timerClockText]
        parts.append(asset.createdAt.formatted(date: .abbreviated, time: .shortened))
        if asset.localOnly { parts.append(String(localized: "this device only")) }
        return parts.joined(separator: " · ")
    }
}
